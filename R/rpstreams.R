#' Bidirectional communication over pipes
#' 
#' The \code{rpstreams} package wraps Jonathan Wakely's pstreams library, which
#' allows communicating with a subprocess using stdin, stdout and stderr.
#' 
#' The \code{\link{pstream}} function opens a stream object linked to a specified
#' command (a program callable from the command line). Three functions:
#' \code{\link{write_stdin}}, \code{\link{read_stdout}} and \code{\link{read_stderr}}
#' can then be used to communicate with the launched proces. \code{\link{status}} will
#' return information about the state of the stream object.
#' 
#' @author Timothy H. Keitt
#'
#' @docType package
#' @name rpstreams
#' 
#' @useDynLib rpstreams
#' @import Rcpp
#' @import methods
NULL

setClass("pstream",
         slots = c(command = "character",
                   args = "character",
                   handle = "externalptr"))

#' Open a pipe stream object
#'
#' Opens a set of pipes to stdin, stdout and stderr for
#' on the specified process.
#' 
#' @param command the program to run
#' @param args a vector of argument strings
#' 
#' @examples
#' # Note: it appears that reading from stdout and stderr
#' # does not work in examples. I suspect those are redirected
#' # by R internally when running examples.
#' x = pstream("R")
#' status(x)
#' read_stderr(x)
#' pstream_close(x)
#' 
#' x = pstream("R", "--vanilla")
#' read_stdout(x)
#' write_stdin(x, "R.Version()")
#' read_stdout(x)
#' send_eof(x); Sys.sleep(1)
#' status(x)
#' 
#' x = pstream("R", "--vanilla")
#' status(x)
#' signal(x); Sys.sleep(1)
#' status(x)
#' 
#' x = pstream("R", "--vanilla")
#' status(x)
#' pstream_close(x)
#' status(x)
#' 
#' @rdname pstream
#' @export
pstream = function(command, args = "")
{
  finalizer.fun = function(handle) close_(handle)
  argv = if(nzchar(args)) c(command, args) else NULL
  s = make_pstream(command, argv)
  if (!is_open_(s)) stop("Could not open stream")
  reg.finalizer(s, finalizer.fun, TRUE)
  new("pstream", command = command, args = args, handle = s)
}

#' @param stream a pstream object
#' @details Closing a stream will wait until the spawned process completes. This
#' can hang your session if the process is not well-behaved. You should manually
#' end the proces if possible. \code{pstream_close} will check whether the program
#' has exited. If it is still running it is sent a SIGTERM signal. The process is then
#' checked for a predetermined number of seconds (set by the compile flag KILL_WAIT_SECONDS).
#' If the process does not exit during that perio, then SIGKILL signal is sent.
#' After that, the stream is manually closed.
#' @rdname pstream
#' @export
pstream_close = function(stream)
{
  close_(stream@handle)
}

#' @rdname pstream
#' @export
send_eof = function(stream)
{
  send_eof_(stream@handle)
}

setMethod("show",
signature("pstream"),
function(object)
{
  cat("stream:", object@command, object@args, "\n")
})

#' Read and write data to process
#' 
#' @param stream a pstream object
#' @param data a vector of values
#' @param send_eof if true, write EOF to stream
#' 
#' # Note: it appears that reading from stdout and stderr
#' # does not work in examples. I suspect those are redirected
#' # by R internally when running examples.
#' x = pstream("R")
#' read_stderr(x)
#' 
#' x = pstream("R", "--vanilla")
#' read_stdout(x)
#' write_stdin(x, "R.Version()")
#' read_stdout(x)
#' write_stdin(x, "q()")
#' 
#' @rdname read-write
#' @export
write_stdin = function(stream, data, send_eof = FALSE)
{
  for (val in data)
    write_stdin_(stream@handle, as.character(val))
  if (send_eof) send_eof_(stream@handle)
  return(invisible(stream))
}

#' @rdname read-write
#' @export
read_stdout = function(stream)
{
  res = read_stdout_(stream@handle)
  class(res) = "rawtext"
  return(res)
}

#' @rdname read-write
#' @export
read_stderr = function(stream)
{
  res = read_stderr_(stream@handle)
  class(res) = "rawtext"
  return(res)
}

#' @export
print.rawtext = function(x, ...) cat(x)

#' Report state of pstream
#' 
#' @param stream a pstream object
#' 
#' @return a boolean
#' 
#' @examples
#' s = pstream("R", "--vanilla")
#' status(s)
#' is_open(s)
#' is_eof(s)
#' is_good(s)
#' is_bad(s)
#' is_fail(s)
#' write_stdin(s, "q()")
#' Sys.sleep(1)
#' has_exited(s)
#' exit_code(s)
#' errno(s)
#' status(s)
#' 
#' @rdname stream-state
#' @export
is_open = function(stream) is_open_(stream@handle)


#' @rdname stream-state
#' @export
is_eof = function(stream) is_eof_(stream@handle)

#' @rdname stream-state
#' @export
is_good = function(stream) is_good_(stream@handle)

#' @rdname stream-state
#' @export
is_bad = function(stream) is_bad_(stream@handle)

#' @rdname stream-state
#' @export
is_fail = function(stream) is_fail_(stream@handle)

#' @rdname stream-state
#' @export
has_exited = function(stream) has_exited_(stream@handle)

#' @rdname stream-state
#' @export
exit_code = function(stream) exit_code_(stream@handle)

#' @rdname stream-state
#' @export
errno = function(stream) errno_(stream@handle)

#' @rdname stream-state
#' @export
status = function(stream)
  c(is_open = is_open(stream),
    is_eof = is_eof(stream),
    is_good = is_good(stream),
    is_bad = is_bad(stream),
    is_fail = is_fail(stream),
    has_exited = has_exited(stream))

#' @param signal the POSIX signal number (see \code{kill -l})
#' @param group signal the entire process group?
#' @rdname pstream
#' @export
signal = function(stream, signal = 15, group = FALSE)
  signal_(stream@handle, signal, group)

#' Rpstreams connections objects
#' 
#' Open an R connection object for reading or writing to process
#' 
#' @param stream a pstream object
#' @param stderr read from stderr?
#' @param send_eof write EOF after sending message?
#' 
#' @details
#' R's \code{\link{connections}} objects provide uniform access to a variety
#' of IO modes. These function build \code{\link{textConnection}} object that
#' read or write to a pstream. An input connection simply reads from stdout,
#' or optionally stderr, and then returns that text when the connection is
#' read. Note that the reading happens at the time of creation.
#' 
#' @return
#' \code{pstream_input_conn:} a \code{\link{textConnection}} object
#' \code{pstream_output_conn:} output connection is a list with two elements: \code{conn} that
#' contains the connection object and \code{flush}, which is a function that
#' writes the data to the pstream. Pass the \code{conn} element to function that
#' operate on connections and then call \code{flush}.
#' 
#' @examples
#' # The examples environment appears to bind stdout
#' # so the output is suppressed. This works typed
#' # into an R session.
#' \dontrun{
#' x = pstream("R", "--vanilla --slave")
#' c1 = pstream_output_conn(x)
#' writeLines("R.Version()", c1$conn)
#' c1$flush()
#' c2 = pstream_input_conn(x)
#' readLines(c2)
#' pstream_close(x)
#' 
#' # send and retreive an R object
#' # works in regular R session
#' x = pstream("R", "--vanilla --slave")
#' a = 1:3
#' write_stdin(x, "a = unserialize(stdin())")
#' c1 = pstream_output_conn(x)
#' serialize(a, c1$conn)
#' c1$flush()
#' write_stdin(x, "serialize(a, stdout())")
#' c2 = pstream_input_conn(x)
#' unserialize(c2)
#' pstream_close(x)
#' }
#' 
#' @rdname pstream-conn
#' @export
pstream_input_conn = function(stream, stderr = FALSE)
{
  msg = if (stderr) read_stderr(stream)
               else read_stdout(stream)
  textConnection(msg)
}

#' @rdname pstream-conn
#' @export
pstream_output_conn = function(stream, send_eof = FALSE)
{
  msg = NULL
  tconn = textConnection("msg", open = "w", local = TRUE)
  f = function() write_stdin(stream, msg, send_eof)
  list(conn = tconn, flush = f)
}
