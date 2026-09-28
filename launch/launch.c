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

#ifndef ENGINE
#define ENGINE "/usr/libexec/x/x-bin"
#endif
#ifndef LAUNCH_DIR
#define LAUNCH_DIR "/usr/share/x/launch/"
#endif
#define APPLETS "coreutils"
#define CALLER_FD 3
#define PATH_LEN 256
#define ARGS_MAX 4096

static void fail(const char *what, const char *arg)
{
	static const char prefix[] = "launch: ";
	write(2, prefix, sizeof prefix - 1);
	write(2, what, strlen(what));
	write(2, arg, strlen(arg));
	write(2, "\n", 1);
	_exit(127);
}

int x_main(int argc, char *argv[]);

int main(int argc, char *argv[])
{
	static char path[PATH_LEN];
	static char *args[ARGS_MAX];
	const char *name = argc > 0 ? argv[0] : "sh";
	const char *slash = strrchr(name, '/');
	int fd, i, n = 0, applet = 0;

	if (slash)
		name = slash + 1;
	/* A login shell arrives as "-sh". */
	if (*name == '-')
		name++;
	if (strcmp(name, "x") == 0)
		return x_main(argc, argv);
	if (strlen(LAUNCH_DIR) + strlen(name) >= PATH_LEN || argc + 4 > ARGS_MAX)
		fail("name or argument list too long: ", name);

	/* The caller's stdin moves first: with 0, 1 and 2 open, the stream
	 * would otherwise be opened on CALLER_FD and overwritten. */
	if (dup2(0, CALLER_FD) < 0)
		fail("cannot keep the caller's stdin for ", name);

	strcpy(path, LAUNCH_DIR);
	strcat(path, name);
	fd = open(path, O_RDONLY);
	if (fd < 0) {
		applet = 1;
		fd = open(LAUNCH_DIR APPLETS, O_RDONLY);
	}
	if (fd < 0)
		fail("no boot stream for ", name);

	if (dup2(fd, 0) < 0)
		fail("cannot put the boot stream on stdin for ", name);
	close(fd);

	args[n++] = ENGINE;
	args[n++] = "--batch";
	if (applet)
		args[n++] = (char *)name;
	for (i = 1; i < argc; i++)
		args[n++] = argv[i];
	args[n] = NULL;

	execv(ENGINE, args);
	fail("cannot run ", ENGINE);
	return 127;
}
