import sys
import itertools
import time


def wait_for_ready(
    is_ready_callback: callable, object_waited_str: str = "X", timeout=None, message=None
):
    """Wait for the object to be ready.
    Args:
        is_ready_callback: Callback to check if the object is ready.
        object_waited_str: String to display in the waiting message.
        timeout: Maximum time to wait in seconds. If None, waits indefinitely.
        message: Text shown while waiting (default: "Waiting for <object_waited_str> to be ready").
    In a terminal, the message is followed by the elapsed seconds and a spinner, so that a long wait
    does not look stuck; otherwise (e.g. output redirected to a log file) only a start line and a
    done line are written.
    """
    message = message or f"Waiting for {object_waited_str} to be ready"
    is_tty = sys.stdout.isatty()
    spinner = itertools.cycle(["|", "/", "-", "\\"])
    start_time = time.time()

    sys.stdout.write(f"{message} ..." if is_tty else f"{message} ...\n")
    sys.stdout.flush()

    while not is_ready_callback():
        elapsed = time.time() - start_time
        if timeout is not None and elapsed > timeout:
            sys.stdout.write("\n")
            raise TimeoutError(f"{object_waited_str} did not become ready within {timeout} seconds")

        if is_tty:
            sys.stdout.write(f"\r{message} ... {elapsed:.0f} s {next(spinner)} ")
            sys.stdout.flush()
        time.sleep(0.1)

    elapsed = time.time() - start_time
    done = f"{message} ... done ({elapsed:.1f} s)"
    sys.stdout.write(f"\r{done}   \n" if is_tty else f"{done}\n")
    sys.stdout.flush()
