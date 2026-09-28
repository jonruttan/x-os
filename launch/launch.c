/*
 * launch -- start the engine on a prepared boot stream, with no shell.
 *
 * The engine reads its program from stdin and finds the caller's stdin on
 * fd 3.  The wrapper script arranges that with a pipe; here the boot stream
 * is a file written when the image was built, so arranging it is two
 * descriptors and an exec.
 *
 * The command name picks the stream: LAUNCH_DIR/NAME when there is one,
 * and otherwise the applet stream, with NAME passed as the first argument.
 * The name x is the x command, which writes its stream as it goes (x.c).
 */
#include <fcntl.h>
#include <string.h>
#include <unistd.h>

#include "x.h"

#ifndef ENGINE
#define ENGINE "/usr/libexec/x/x-bin"
#endif
#ifndef LAUNCH_DIR
#define LAUNCH_DIR "/usr/share/x/launch/"
#endif
#define APPLET_STREAM "coreutils"
#define CALLER_FD 3
#define PATH_LEN 256
#define ARGS_MAX 4096

/**
 * Report an error on stderr and exit with the status of a command that
 * could not be run.
 *
 * @param message  const char* -- What went wrong
 * @param subject  const char* -- What it went wrong with
 */
static void exit_with_error(const char *message, const char *subject)
{
	static const char prefix[] = "launch: ";

	write(2, prefix, sizeof prefix - 1);
	write(2, message, strlen(message));
	write(2, subject, strlen(subject));
	write(2, "\n", 1);
	_exit(127);
}

/**
 * The name the launcher was invoked by, without its directory, and without
 * the dash a login shell arrives with.
 *
 * @param argc  int -- Argument count
 * @param argv  char** -- Arguments; argv[0] is the invoked name
 * @return const char* -- The command's name
 */
static const char *invoked_name(int argc, char *argv[])
{
	const char *name = argc > 0 ? argv[0] : "sh";
	const char *slash = strrchr(name, '/');

	if (slash) {
		name = slash + 1;
	}
	if (*name == '-') {
		name++;
	}

	return name;
}

/**
 * Open a command's boot stream.  A command with no stream of its own is an
 * applet, and gets the applet stream.
 *
 * @param name       const char* -- The command's name
 * @param is_applet  int* -- Set to 1 when the applet stream was opened
 * @return int -- The stream's descriptor, or -1 when there is none
 */
static int open_boot_stream(const char *name, int *is_applet)
{
	static char path[PATH_LEN];
	int fd;

	strcpy(path, LAUNCH_DIR);
	strcat(path, name);
	*is_applet = 0;

	fd = open(path, O_RDONLY);
	if (fd < 0) {
		*is_applet = 1;
		fd = open(LAUNCH_DIR APPLET_STREAM, O_RDONLY);
	}

	return fd;
}

int main(int argc, char *argv[])
{
	static char *engine_argv[ARGS_MAX];
	const char *name = invoked_name(argc, argv);
	int stream_fd, is_applet, i, count = 0;

	if (strcmp(name, "x") == 0) {
		return run_x_command(argc, argv);
	}
	if (strlen(LAUNCH_DIR) + strlen(name) >= PATH_LEN || argc + 4 > ARGS_MAX) {
		exit_with_error("name or argument list too long: ", name);
	}

	/* The caller's stdin moves first: with 0, 1 and 2 open, the stream
	 * would otherwise be opened on CALLER_FD and overwritten. */
	if (dup2(0, CALLER_FD) < 0) {
		exit_with_error("cannot keep the caller's stdin for ", name);
	}

	stream_fd = open_boot_stream(name, &is_applet);
	if (stream_fd < 0) {
		exit_with_error("no boot stream for ", name);
	}
	if (dup2(stream_fd, 0) < 0) {
		exit_with_error("cannot put the boot stream on stdin for ", name);
	}
	close(stream_fd);

	engine_argv[count++] = ENGINE;
	engine_argv[count++] = "--batch";
	if (is_applet) {
		engine_argv[count++] = (char *)name;
	}
	for (i = 1; i < argc; i++) {
		engine_argv[count++] = argv[i];
	}
	engine_argv[count] = NULL;

	execv(ENGINE, engine_argv);
	exit_with_error("cannot run ", ENGINE);

	return 127;
}
