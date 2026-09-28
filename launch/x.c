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
#include <stdio.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <unistd.h>

#ifndef ENGINE
#define ENGINE "/usr/libexec/x/x-bin"
#endif
#ifndef SHARE
#define SHARE "/usr/share/x"
#endif

#define CALLER_FD 3
#define PATH_LEN 512
#define LIST_MAX 256

static const char reset_form[] = "(set! %batch? ())\n";

/* A piece of the stream: text, a file, or the caller's stdin. */
struct piece {
	const char *text;
	const char *path;
	int is_stdin;
};

static struct piece pieces[LIST_MAX];
static int npieces;

static void say(const char *a, const char *b, const char *c)
{
	write(2, "x: ", 3);
	write(2, a, strlen(a));
	if (b)
		write(2, b, strlen(b));
	if (c)
		write(2, c, strlen(c));
	write(2, "\n", 1);
}

static int fail(const char *a, const char *b, const char *c)
{
	say(a, b, c);
	return 1;
}

static int add(const char *text, const char *path, int is_stdin)
{
	if (npieces >= LIST_MAX)
		return fail("too many pieces", NULL, NULL);
	pieces[npieces].text = text;
	pieces[npieces].path = path;
	pieces[npieces].is_stdin = is_stdin;
	npieces++;
	return 0;
}

static int exists(const char *path)
{
	struct stat st;
	return stat(path, &st) == 0;
}

static int join(char *out, const char *a, const char *b, const char *c,
		const char *d)
{
	size_t n = strlen(a) + strlen(b) + strlen(c) + strlen(d);
	if (n >= PATH_LEN)
		return -1;
	strcpy(out, a);
	strcat(out, b);
	strcat(out, c);
	strcat(out, d);
	return 0;
}

static int write_all(int fd, const char *s, size_t n)
{
	while (n > 0) {
		ssize_t w = write(fd, s, n);
		if (w < 0) {
			if (errno == EINTR)
				continue;
			return -1;
		}
		s += w;
		n -= (size_t)w;
	}
	return 0;
}

static int copy_fd(int from, int to)
{
	char buf[16384];
	for (;;) {
		ssize_t r = read(from, buf, sizeof buf);
		if (r == 0)
			return 0;
		if (r < 0) {
			if (errno == EINTR)
				continue;
			return -1;
		}
		if (write_all(to, buf, (size_t)r) < 0)
			return -1;
	}
}

/* Write every piece to fd.  A write the engine will not take ends it: the
 * engine has stopped reading, and what it answers is the verdict. */
static void write_pieces(int fd)
{
	int i;
	for (i = 0; i < npieces; i++) {
		if (pieces[i].text) {
			if (write_all(fd, pieces[i].text, strlen(pieces[i].text)) < 0)
				return;
		} else if (pieces[i].is_stdin) {
			if (copy_fd(0, fd) < 0)
				return;
		} else {
			int in = open(pieces[i].path, O_RDONLY);
			if (in < 0) {
				say("cannot open ", pieces[i].path, NULL);
				return;
			}
			if (copy_fd(in, fd) < 0) {
				close(in);
				return;
			}
			close(in);
		}
	}
}

static void usage(void)
{
	static const char text[] =
		"usage: x [options] [--] [arg...]\n"
		"  -l LANG        a dialect (x, xe) or an installed lang\n"
		"  -c EXPR        evaluate EXPR, then exit; repeatable\n"
		"  -f FILE        evaluate FILE, then exit\n"
		"  -F FILE        evaluate FILE, then the session; repeatable\n"
		"  -q, --quiet    no banner\n"
		"  --no-color     no colour\n"
		"  --share-dir    print the library's directory\n"
		"  --engine-path  print the engine's path\n"
		"  -v, --verbose  print the stream's pieces to stderr\n"
		"With no -c or -f, piped stdin is the program; a terminal is a session.\n";
	write(1, text, sizeof text - 1);
}

int x_main(int argc, char *argv[])
{
	static char image[PATH_LEN], entry[PATH_LEN], loader[PATH_LEN];
	static char launcher[PATH_LEN], dialect_entry[PATH_LEN], lang_decl[PATH_LEN];
	static char img_form[PATH_LEN + 32];
	static const char *files[LIST_MAX], *evals[LIST_MAX], *flags[LIST_MAX];
	static char *args[LIST_MAX + 8];
	const char *lang = NULL, *file1 = NULL;
	int nfiles = 0, nevals = 0, nflags = 0, n = 0;
	int post = 0, verbose = 0, bundle, batch, stdin_prog = 0, reset;
	int i = 1, p[2], status;
	pid_t pid;

	for (; i < argc; i++) {
		const char *a = argv[i];
		int more = i + 1 < argc;
		if (!strcmp(a, "-l") || !strcmp(a, "--lib")) {
			if (!more)
				return fail(a, ": needs a lang", NULL);
			if (lang)
				return fail("one -l here", NULL, NULL);
			lang = argv[++i];
		} else if (!strcmp(a, "-c") || !strcmp(a, "--eval")) {
			if (!more)
				return fail(a, ": needs an expression", NULL);
			if (nevals >= LIST_MAX)
				return fail("too many -c", NULL, NULL);
			evals[nevals++] = argv[++i];
		} else if (!strcmp(a, "-f") || !strcmp(a, "--file")) {
			if (!more)
				return fail(a, ": needs a file", NULL);
			files[0] = argv[++i];
			nfiles = 1;
			if (!file1)
				file1 = files[0];
			post = 0;
		} else if (!strcmp(a, "-F") || !strcmp(a, "--load")) {
			if (!more)
				return fail(a, ": needs a file", NULL);
			if (nfiles >= LIST_MAX)
				return fail("too many -F", NULL, NULL);
			memmove(files + 1, files, (size_t)nfiles * sizeof *files);
			files[0] = argv[++i];
			nfiles++;
			if (!file1)
				file1 = files[0];
			post = 1;
		} else if (!strcmp(a, "-q") || !strcmp(a, "--quiet")) {
			flags[nflags++] = "--quiet";
		} else if (!strcmp(a, "--no-color")) {
			flags[nflags++] = "--no-color";
		} else if (!strcmp(a, "-v") || !strcmp(a, "--verbose")) {
			verbose = 1;
		} else if (!strcmp(a, "-h") || !strcmp(a, "--help")) {
			usage();
			return 0;
		} else if (!strcmp(a, "--share-dir")) {
			write(1, SHARE "\n", sizeof SHARE);
			return 0;
		} else if (!strcmp(a, "--engine-path")) {
			write(1, ENGINE "\n", sizeof ENGINE);
			return 0;
		} else if (!strcmp(a, "--")) {
			i++;
			break;
		} else if (a[0] == '-') {
			return fail("unknown option: ", a, NULL);
		} else {
			break;
		}
		if (nflags >= LIST_MAX)
			return fail("too many flags", NULL, NULL);
	}

	/* A dialect has an entry among the boot files; a lang has a
	 * declaration among the langs.  Either boots from its state image. */
	if (!lang)
		lang = "x";
	if (strchr(lang, '/') || lang[0] == '.' || lang[0] == '\0')
		return fail("no lang named '", lang, "'");
	if (join(dialect_entry, SHARE "/boot/", lang, ".x", "") < 0
	    || join(lang_decl, SHARE "/langs/", lang, "/lang.xon", "") < 0)
		return fail("lang name too long: ", lang, NULL);
	if (exists(dialect_entry)) {
		bundle = 0;
		join(image, SHARE "/images/", lang, ".boot.x.ximg", "");
	} else if (exists(lang_decl)) {
		bundle = 1;
		join(image, SHARE "/langs/", lang, "/.images/", "");
		if (join(image, image, lang, ".boot.x.ximg", "") < 0)
			return fail("lang name too long: ", lang, NULL);
		join(entry, SHARE "/langs/", lang, "/run.x", "");
	} else {
		return fail("no dialect or lang named '", lang, "'");
	}
	if (!exists(image))
		return fail("no state image for ", lang, NULL);
	join(loader, SHARE "/launch/", "image-loader", "", "");
	join(launcher, SHARE "/lib/x/repl/launch.x", "", "", "");

	/* The wrapper's rules: a lang's entry counts as a file, a file or an
	 * expression means batch, and with neither a piped stdin is the
	 * program.  The launcher is owed to a session, and an expression
	 * ends the run, so it takes the launcher away. */
	if (bundle && !file1)
		post = 1;
	batch = nfiles > 0 || bundle || nevals > 0;
	if (!batch && !isatty(0)) {
		stdin_prog = 1;
		batch = 1;
	}
	if (nevals > 0)
		post = 0;
	if (bundle) {
		reset = !file1;
	} else {
		reset = nfiles == 0 && nevals == 0 && !stdin_prog;
		if (reset)
			post = 1;
	}

	strcpy(img_form, "(def %IMG-PATH \"");
	strcat(img_form, image);
	strcat(img_form, "\")\n");
	if (add(img_form, NULL, 0) || add(NULL, loader, 0))
		return 1;
	if (reset && add(reset_form, NULL, 0))
		return 1;
	if (bundle && add(NULL, entry, 0))
		return 1;
	for (n = 0; n < nfiles; n++)
		if (add(NULL, files[n], 0))
			return 1;
	if (stdin_prog && add(NULL, NULL, 1))
		return 1;
	for (n = 0; n < nevals; n++)
		if (add(evals[n], NULL, 0) || add("\n", NULL, 0))
			return 1;
	if (post && add(NULL, launcher, 0))
		return 1;

	/* The engine's argv: its path, the flags, --batch, the arguments. */
	n = 0;
	args[n++] = ENGINE;
	for (p[0] = 0; p[0] < nflags; p[0]++)
		args[n++] = (char *)flags[p[0]];
	if (batch)
		args[n++] = "--batch";
	for (; i < argc && n < LIST_MAX + 7; i++)
		args[n++] = argv[i];
	args[n] = NULL;

	if (verbose) {
		for (p[0] = 0; p[0] < npieces; p[0]++)
			say(pieces[p[0]].is_stdin ? "stdin"
			    : pieces[p[0]].path ? pieces[p[0]].path
			    : pieces[p[0]].text, NULL, NULL);
		for (p[0] = 0; p[0] < n; p[0]++)
			say("argv: ", args[p[0]], NULL);
	}

	/* Every piece is checked before the engine starts, so a missing file
	 * is reported by name and not as whatever the engine makes of a
	 * stream that stops. */
	for (n = 0; n < nfiles; n++)
		if (access(files[n], R_OK) < 0)
			return fail("cannot open ", files[n], NULL);

	/* The caller's stdin moves first: with 0, 1 and 2 open, the pipe would
	 * otherwise be made on CALLER_FD and overwritten. */
	if (dup2(0, CALLER_FD) < 0)
		return fail("cannot keep the caller's stdin", NULL, NULL);
	if (pipe(p) < 0)
		return fail("cannot make a pipe", NULL, NULL);
	pid = fork();
	if (pid < 0)
		return fail("cannot fork", NULL, NULL);
	if (pid == 0) {
		if (dup2(p[0], 0) < 0)
			_exit(fail("cannot arrange descriptors", NULL, NULL) + 126);
		close(p[0]);
		close(p[1]);
		execv(ENGINE, args);
		_exit(fail("cannot run ", ENGINE, NULL) + 126);
	}

	/* A key the terminal turns into a signal is the engine's to answer:
	 * this process only writes, and waits. */
	signal(SIGINT, SIG_IGN);
	signal(SIGQUIT, SIG_IGN);
	signal(SIGPIPE, SIG_IGN);
	close(CALLER_FD);
	close(p[0]);
	write_pieces(p[1]);
	close(p[1]);

	while (waitpid(pid, &status, 0) < 0)
		if (errno != EINTR)
			return fail("lost the engine", NULL, NULL);
	if (WIFEXITED(status))
		return WEXITSTATUS(status);
	if (WIFSIGNALED(status)) {
		signal(WTERMSIG(status), SIG_DFL);
		kill(getpid(), WTERMSIG(status));
		return 128 + WTERMSIG(status);
	}
	return 1;
}
