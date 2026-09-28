/*
 * x -- the x command, for a tree that boots every lang from its state image.
 *
 *   x [-q] [--no-color] [-l LANG] [-c EXPR]... [-f FILE] [-F FILE]... [--] [ARG...]
 *
 * It writes the stream the wrapper script (x.sh) writes for a boot from a
 * state image, and runs the engine on it, with the caller's stdin on fd 3:
 *
 *   (def %IMG-PATH "IMAGE")      the lang's state image
 *   the image loader              lib/img.x and tools/dev/image-read.x
 *   (set! %batch? ())             when there is a session to hand over
 *   the lang's entry              a lang bundle's run.x
 *   the files                     -F's, then -f's
 *   stdin                         piped program text, for a dialect
 *   the expressions               -c's, one a line
 *   the launcher                  lib/x/repl/launch.x, when a session is owed
 *
 * The arguments after the options reach the engine after its flags, as the
 * wrapper passes them.  A lang with no state image is an error: there is no
 * wrapper here to boot one from source.
 *
 * This process writes the stream and the engine reads it, so the engine is
 * a child: a stream longer than a pipe holds, or a piped program, is written
 * while it runs.  This process then answers what the engine did.
 */
#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <unistd.h>

#include "x.h"

#ifndef ENGINE
#define ENGINE "/usr/libexec/x/x-bin"
#endif
#ifndef SHARE
#define SHARE "/usr/share/x"
#endif

#define IMAGE_LOADER SHARE "/launch/image-loader"
#define SESSION_LAUNCHER SHARE "/lib/x/repl/launch.x"
#define DEFAULT_LANG "x"

#define CALLER_FD 3
#define PATH_LEN 512
#define LIST_MAX 256

static const char batch_reset_form[] = "(set! %batch? ())\n";

/** What a piece of the stream is read from. */
enum piece_kind {
	PIECE_TEXT,
	PIECE_FILE,
	PIECE_CALLER_STDIN
};

/** A piece of the stream: text, a file's path, or the caller's stdin. */
struct stream_piece {
	enum piece_kind kind;
	const char *value;
};

/** The stream the engine reads, in order. */
struct stream {
	struct stream_piece pieces[LIST_MAX];
	int count;
	char image_form[PATH_LEN + 32];
};

/** What the command line asks for. */
struct options {
	const char *lang_name;
	const char *first_file;
	const char *files[LIST_MAX];
	int file_count;
	const char *expressions[LIST_MAX];
	int expression_count;
	const char *engine_flags[LIST_MAX];
	int engine_flag_count;
	int session_after_files;
	int verbose;
	char **arguments;
	int argument_count;
};

/** A dialect or a lang bundle, and where its pieces are. */
struct lang {
	int is_bundle;
	char image[PATH_LEN];
	char entry[PATH_LEN];
};

/** What reading the command line leaves to do. */
enum options_result {
	OPTIONS_RUN,
	OPTIONS_DONE,
	OPTIONS_FAILED
};

/**
 * Report an error on stderr, as `x: MESSAGE SUBJECT TRAILER`.
 *
 * @param message  const char* -- What went wrong
 * @param subject  const char* -- What it went wrong with, or NULL
 * @param trailer  const char* -- Text after the subject, or NULL
 */
static void print_error(const char *message, const char *subject,
	const char *trailer)
{
	write(2, "x: ", 3);
	write(2, message, strlen(message));
	if (subject) {
		write(2, subject, strlen(subject));
	}
	if (trailer) {
		write(2, trailer, strlen(trailer));
	}
	write(2, "\n", 1);
}

/**
 * Append a part to a path, refusing a path longer than PATH_LEN.
 *
 * @param path  char* -- The path so far; PATH_LEN bytes
 * @param part  const char* -- The part to append
 * @return int -- 0, or -1 when the result would not fit
 */
static int path_append(char *path, const char *part)
{
	if (strlen(path) + strlen(part) >= PATH_LEN) {
		return -1;
	}
	strcat(path, part);

	return 0;
}

/**
 * Whether anything is at a path.
 *
 * @param path  const char* -- The path
 * @return int -- 1 when there is, 0 when there is not
 */
static int path_exists(const char *path)
{
	struct stat st;

	return stat(path, &st) == 0;
}

/**
 * Write all of a buffer to a descriptor, through short writes and
 * interruptions.
 *
 * @param fd      int -- The descriptor
 * @param text    const char* -- The bytes
 * @param length  size_t -- How many
 * @return int -- 0, or -1 when a write fails
 */
static int write_fully(int fd, const char *text, size_t length)
{
	ssize_t written;

	while (length > 0) {
		written = write(fd, text, length);
		if (written < 0) {
			if (errno == EINTR) {
				continue;
			}
			return -1;
		}
		text += written;
		length -= (size_t)written;
	}

	return 0;
}

/**
 * Copy one descriptor to another until the first ends.
 *
 * @param from  int -- The descriptor read
 * @param to    int -- The descriptor written
 * @return int -- 0 at the end of `from`, or -1 when a read or a write fails
 */
static int copy_descriptor(int from, int to)
{
	char buffer[16384];
	ssize_t got;

	for (;;) {
		got = read(from, buffer, sizeof buffer);
		if (got == 0) {
			return 0;
		}
		if (got < 0) {
			if (errno == EINTR) {
				continue;
			}
			return -1;
		}
		if (write_fully(to, buffer, (size_t)got) < 0) {
			return -1;
		}
	}
}

/**
 * Append a piece to the stream.
 *
 * @param stream  struct stream* -- The stream
 * @param kind    enum piece_kind -- What the piece is read from
 * @param value   const char* -- The text, or the file's path
 * @return int -- 0, or -1 when the stream is full
 */
static int stream_add(struct stream *stream, enum piece_kind kind,
	const char *value)
{
	if (stream->count >= LIST_MAX) {
		print_error("too many pieces in the stream", NULL, NULL);
		return -1;
	}
	stream->pieces[stream->count].kind = kind;
	stream->pieces[stream->count].value = value;
	stream->count++;

	return 0;
}

/**
 * Write every piece of the stream to a descriptor.  A write the engine will
 * not take ends it: the engine has stopped reading, and what it answers is
 * the verdict.
 *
 * @param stream  const struct stream* -- The stream
 * @param fd      int -- The descriptor the engine reads
 */
static void stream_write(const struct stream *stream, int fd)
{
	const struct stream_piece *piece;
	int i, file_fd, result;

	for (i = 0; i < stream->count; i++) {
		piece = &stream->pieces[i];

		if (piece->kind == PIECE_TEXT) {
			result = write_fully(fd, piece->value, strlen(piece->value));
		}
		else if (piece->kind == PIECE_CALLER_STDIN) {
			result = copy_descriptor(0, fd);
		}
		else {
			file_fd = open(piece->value, O_RDONLY);
			if (file_fd < 0) {
				print_error("cannot open ", piece->value, NULL);
				return;
			}
			result = copy_descriptor(file_fd, fd);
			close(file_fd);
		}

		if (result < 0) {
			return;
		}
	}
}

/**
 * Print the stream's pieces and the engine's argv on stderr, for -v.
 *
 * @param stream       const struct stream* -- The stream
 * @param engine_argv  char** -- The engine's argv, NULL-terminated
 */
static void stream_print(const struct stream *stream, char *engine_argv[])
{
	const struct stream_piece *piece;
	int i;

	for (i = 0; i < stream->count; i++) {
		piece = &stream->pieces[i];
		if (piece->kind == PIECE_CALLER_STDIN) {
			print_error("piece: stdin", NULL, NULL);
		}
		else {
			print_error("piece: ", piece->value, NULL);
		}
	}
	for (i = 0; engine_argv[i]; i++) {
		print_error("argv: ", engine_argv[i], NULL);
	}
}

/** Print how the command is used, on stdout. */
static void print_usage(void)
{
	static const char *const lines[] = {
		"usage: x [options] [--] [arg...]",
		"  -l LANG        a dialect (x, xe) or an installed lang",
		"  -c EXPR        evaluate EXPR, then exit; repeatable",
		"  -f FILE        evaluate FILE, then exit",
		"  -F FILE        evaluate FILE, then the session; repeatable",
		"  -q, --quiet    no banner",
		"  --no-color     no colour",
		"  --share-dir    print the library's directory",
		"  --engine-path  print the engine's path",
		"  -v, --verbose  print the stream's pieces to stderr",
		"With no -c or -f, piped stdin is the program; a terminal is a session.",
		NULL
	};
	int i;

	for (i = 0; lines[i]; i++) {
		write(1, lines[i], strlen(lines[i]));
		write(1, "\n", 1);
	}
}

/**
 * The value an option takes: the argument after it.
 *
 * @param argc   int -- Argument count
 * @param argv   char** -- Arguments
 * @param index  int* -- The option's index; moved to its value's
 * @param what   const char* -- What the value is, for the error
 * @return const char* -- The value, or NULL when there is none
 */
static const char *option_value(int argc, char *argv[], int *index,
	const char *what)
{
	if (*index + 1 >= argc) {
		print_error(argv[*index], ": needs ", what);
		return NULL;
	}
	*index += 1;

	return argv[*index];
}

/**
 * Read the command line into options.
 *
 * @param argc     int -- Argument count
 * @param argv     char** -- Arguments
 * @param options  struct options* -- Filled in
 * @return enum options_result -- Whether to run, to stop, or to fail
 */
static enum options_result read_options(int argc, char *argv[],
	struct options *options)
{
	const char *arg, *value;
	int i;

	for (i = 1; i < argc; i++) {
		arg = argv[i];

		if (strcmp(arg, "-l") == 0 || strcmp(arg, "--lib") == 0) {
			value = option_value(argc, argv, &i, "a lang");
			if ( ! value) {
				return OPTIONS_FAILED;
			}
			if (options->lang_name) {
				print_error("one -l here", NULL, NULL);
				return OPTIONS_FAILED;
			}
			options->lang_name = value;
		}
		else if (strcmp(arg, "-c") == 0 || strcmp(arg, "--eval") == 0) {
			value = option_value(argc, argv, &i, "an expression");
			if ( ! value) {
				return OPTIONS_FAILED;
			}
			if (options->expression_count >= LIST_MAX) {
				print_error("too many -c", NULL, NULL);
				return OPTIONS_FAILED;
			}
			options->expressions[options->expression_count++] = value;
		}
		else if (strcmp(arg, "-f") == 0 || strcmp(arg, "--file") == 0) {
			/* -f names the one file to run: it takes the place of any
			 * named before it, as the wrapper has it. */
			value = option_value(argc, argv, &i, "a file");
			if ( ! value) {
				return OPTIONS_FAILED;
			}
			options->files[0] = value;
			options->file_count = 1;
			if ( ! options->first_file) {
				options->first_file = value;
			}
			options->session_after_files = 0;
		}
		else if (strcmp(arg, "-F") == 0 || strcmp(arg, "--load") == 0) {
			/* -F loads a file ahead of the ones named before it, and
			 * the session follows. */
			value = option_value(argc, argv, &i, "a file");
			if ( ! value) {
				return OPTIONS_FAILED;
			}
			if (options->file_count >= LIST_MAX) {
				print_error("too many -F", NULL, NULL);
				return OPTIONS_FAILED;
			}
			memmove(options->files + 1, options->files,
				(size_t)options->file_count * sizeof *options->files);
			options->files[0] = value;
			options->file_count++;
			if ( ! options->first_file) {
				options->first_file = value;
			}
			options->session_after_files = 1;
		}
		else if (strcmp(arg, "-q") == 0 || strcmp(arg, "--quiet") == 0) {
			options->engine_flags[options->engine_flag_count++] = "--quiet";
		}
		else if (strcmp(arg, "--no-color") == 0) {
			options->engine_flags[options->engine_flag_count++] = "--no-color";
		}
		else if (strcmp(arg, "-v") == 0 || strcmp(arg, "--verbose") == 0) {
			options->verbose = 1;
		}
		else if (strcmp(arg, "-h") == 0 || strcmp(arg, "--help") == 0) {
			print_usage();
			return OPTIONS_DONE;
		}
		else if (strcmp(arg, "--share-dir") == 0) {
			write(1, SHARE "\n", sizeof SHARE);
			return OPTIONS_DONE;
		}
		else if (strcmp(arg, "--engine-path") == 0) {
			write(1, ENGINE "\n", sizeof ENGINE);
			return OPTIONS_DONE;
		}
		else if (strcmp(arg, "--") == 0) {
			i++;
			break;
		}
		else if (arg[0] == '-') {
			print_error("unknown option: ", arg, NULL);
			return OPTIONS_FAILED;
		}
		else {
			break;
		}

		if (options->engine_flag_count >= LIST_MAX) {
			print_error("too many flags", NULL, NULL);
			return OPTIONS_FAILED;
		}
	}

	options->arguments = argv + i;
	options->argument_count = argc - i;

	return OPTIONS_RUN;
}

/**
 * Find a dialect or a lang bundle by name.  A dialect has an entry among
 * the boot files; a lang has a declaration among the langs.  Either boots
 * from its state image, which must be there.
 *
 * @param name  const char* -- The name -l gave, or the default
 * @param lang  struct lang* -- Filled in
 * @return int -- 0, or -1 when there is no such lang or no image for it
 */
static int find_lang(const char *name, struct lang *lang)
{
	char dialect_entry[PATH_LEN] = "", declaration[PATH_LEN] = "";

	if (name[0] == '\0' || name[0] == '.' || strchr(name, '/')) {
		print_error("no dialect or lang named '", name, "'");
		return -1;
	}
	if (path_append(dialect_entry, SHARE "/boot/") < 0
		|| path_append(dialect_entry, name) < 0
		|| path_append(dialect_entry, ".x") < 0
		|| path_append(declaration, SHARE "/langs/") < 0
		|| path_append(declaration, name) < 0
		|| path_append(declaration, "/lang.xon") < 0) {
		print_error("lang name too long: ", name, NULL);
		return -1;
	}

	lang->image[0] = '\0';
	lang->entry[0] = '\0';

	if (path_exists(dialect_entry)) {
		lang->is_bundle = 0;
		path_append(lang->image, SHARE "/images/");
		path_append(lang->image, name);
		path_append(lang->image, ".boot.x.ximg");
	}
	else if (path_exists(declaration)) {
		lang->is_bundle = 1;
		path_append(lang->image, SHARE "/langs/");
		path_append(lang->image, name);
		path_append(lang->image, "/.images/");
		path_append(lang->image, name);
		path_append(lang->image, ".boot.x.ximg");
		path_append(lang->entry, SHARE "/langs/");
		path_append(lang->entry, name);
		path_append(lang->entry, "/run.x");
	}
	else {
		print_error("no dialect or lang named '", name, "'");
		return -1;
	}

	if ( ! path_exists(lang->image)) {
		print_error("no state image for ", name, NULL);
		return -1;
	}

	return 0;
}

/**
 * Compose the stream by the wrapper's rules.  A lang's entry counts as a
 * file, a file or an expression means batch, and with neither a piped stdin
 * is the program.  The launcher is owed to a session, and an expression
 * ends the run, so it takes the launcher away.
 *
 * @param options  const struct options* -- What the command line asks for
 * @param lang     const struct lang* -- The lang
 * @param stream   struct stream* -- Filled in
 * @param batch    int* -- Set to 1 when the engine runs in batch
 * @return int -- 0, or -1 when the stream is full
 */
static int compose_stream(const struct options *options,
	const struct lang *lang, struct stream *stream, int *batch)
{
	int session_owed, stdin_is_program = 0, batch_reset, i;

	session_owed = options->session_after_files;
	if (lang->is_bundle && ! options->first_file) {
		session_owed = 1;
	}

	*batch = options->file_count > 0 || lang->is_bundle
		|| options->expression_count > 0;
	if ( ! *batch && ! isatty(0)) {
		stdin_is_program = 1;
		*batch = 1;
	}
	if (options->expression_count > 0) {
		session_owed = 0;
	}

	if (lang->is_bundle) {
		batch_reset = ! options->first_file;
	}
	else {
		batch_reset = options->file_count == 0
			&& options->expression_count == 0 && ! stdin_is_program;
		if (batch_reset) {
			session_owed = 1;
		}
	}

	strcpy(stream->image_form, "(def %IMG-PATH \"");
	strcat(stream->image_form, lang->image);
	strcat(stream->image_form, "\")\n");

	if (stream_add(stream, PIECE_TEXT, stream->image_form) < 0
		|| stream_add(stream, PIECE_FILE, IMAGE_LOADER) < 0) {
		return -1;
	}
	if (batch_reset && stream_add(stream, PIECE_TEXT, batch_reset_form) < 0) {
		return -1;
	}
	if (lang->is_bundle && stream_add(stream, PIECE_FILE, lang->entry) < 0) {
		return -1;
	}
	for (i = 0; i < options->file_count; i++) {
		if (stream_add(stream, PIECE_FILE, options->files[i]) < 0) {
			return -1;
		}
	}
	if (stdin_is_program && stream_add(stream, PIECE_CALLER_STDIN, NULL) < 0) {
		return -1;
	}
	for (i = 0; i < options->expression_count; i++) {
		if (stream_add(stream, PIECE_TEXT, options->expressions[i]) < 0
			|| stream_add(stream, PIECE_TEXT, "\n") < 0) {
			return -1;
		}
	}
	if (session_owed && stream_add(stream, PIECE_FILE, SESSION_LAUNCHER) < 0) {
		return -1;
	}

	return 0;
}

/**
 * Build the engine's argv: its path, the flags, --batch, the arguments.
 *
 * @param options      const struct options* -- What the command line asks for
 * @param batch        int -- Whether the engine runs in batch
 * @param engine_argv  char** -- Filled in and NULL-terminated; LIST_MAX + 2
 *                     entries past the flags
 * @return int -- 0, or -1 when there are too many arguments
 */
static int build_engine_argv(const struct options *options, int batch,
	char *engine_argv[])
{
	int count = 0, i;

	if (options->argument_count > LIST_MAX) {
		print_error("too many arguments", NULL, NULL);
		return -1;
	}

	engine_argv[count++] = ENGINE;
	for (i = 0; i < options->engine_flag_count; i++) {
		engine_argv[count++] = (char *)options->engine_flags[i];
	}
	if (batch) {
		engine_argv[count++] = "--batch";
	}
	for (i = 0; i < options->argument_count; i++) {
		engine_argv[count++] = options->arguments[i];
	}
	engine_argv[count] = NULL;

	return 0;
}

/**
 * Run the engine on the stream: the engine is a child reading a pipe with
 * the caller's stdin on CALLER_FD, and this process writes the stream into
 * the pipe and waits.
 *
 * @param stream       const struct stream* -- The stream
 * @param engine_argv  char** -- The engine's argv
 * @return int -- The engine's exit status, or 128 plus the signal that
 *         ended it
 */
static int run_engine(const struct stream *stream, char *engine_argv[])
{
	int pipe_fds[2], status;
	pid_t pid;

	/* The caller's stdin moves first: with 0, 1 and 2 open, the pipe would
	 * otherwise be made on CALLER_FD and overwritten. */
	if (dup2(0, CALLER_FD) < 0) {
		print_error("cannot keep the caller's stdin", NULL, NULL);
		return 1;
	}
	if (pipe(pipe_fds) < 0) {
		print_error("cannot make a pipe", NULL, NULL);
		return 1;
	}

	pid = fork();
	if (pid < 0) {
		print_error("cannot fork", NULL, NULL);
		return 1;
	}
	if (pid == 0) {
		if (dup2(pipe_fds[0], 0) < 0) {
			print_error("cannot put the stream on stdin", NULL, NULL);
			_exit(127);
		}
		close(pipe_fds[0]);
		close(pipe_fds[1]);
		execv(ENGINE, engine_argv);
		print_error("cannot run ", ENGINE, NULL);
		_exit(127);
	}

	/* A key the terminal turns into a signal is the engine's to answer:
	 * this process only writes, and waits. */
	signal(SIGINT, SIG_IGN);
	signal(SIGQUIT, SIG_IGN);
	signal(SIGPIPE, SIG_IGN);
	close(CALLER_FD);
	close(pipe_fds[0]);
	stream_write(stream, pipe_fds[1]);
	close(pipe_fds[1]);

	while (waitpid(pid, &status, 0) < 0) {
		if (errno != EINTR) {
			print_error("lost the engine", NULL, NULL);
			return 1;
		}
	}

	if (WIFEXITED(status)) {
		return WEXITSTATUS(status);
	}
	if (WIFSIGNALED(status)) {
		signal(WTERMSIG(status), SIG_DFL);
		kill(getpid(), WTERMSIG(status));
		return 128 + WTERMSIG(status);
	}

	return 1;
}

/**
 * The x command: read the options, find the lang, compose its stream, and
 * run the engine on it.
 *
 * @param argc  int -- Argument count
 * @param argv  char** -- Arguments
 * @return int -- The exit status
 */
int run_x_command(int argc, char *argv[])
{
	static struct options options;
	static struct lang lang;
	static struct stream stream;
	static char *engine_argv[2 * LIST_MAX + 4];
	enum options_result result;
	int batch, i;

	result = read_options(argc, argv, &options);
	if (result == OPTIONS_DONE) {
		return 0;
	}
	if (result == OPTIONS_FAILED) {
		return 1;
	}

	if (find_lang(options.lang_name ? options.lang_name : DEFAULT_LANG,
		&lang) < 0) {
		return 1;
	}
	if (compose_stream(&options, &lang, &stream, &batch) < 0) {
		return 1;
	}
	if (build_engine_argv(&options, batch, engine_argv) < 0) {
		return 1;
	}
	if (options.verbose) {
		stream_print(&stream, engine_argv);
	}

	/* Every file is checked before the engine starts, so a missing one is
	 * reported by name and not as whatever the engine makes of a stream
	 * that stops. */
	for (i = 0; i < options.file_count; i++) {
		if (access(options.files[i], R_OK) < 0) {
			print_error("cannot open ", options.files[i], NULL);
			return 1;
		}
	}

	return run_engine(&stream, engine_argv);
}
