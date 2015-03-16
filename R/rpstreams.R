#' Bidirectional, non-blocking communication over pipes
#' 
#' The \code{rpstreams} package wraps Jonathan Wakely's pstreams library, which
#' allows communicating with a subprocess using stdin, stdout and stderr. All
#' reads are non-blocking.
#' 
#' The \code{\link{pstream}} function opens a stream object linked to a specified
#' command (a program callable from the command line). Three functions:
#' \code{\link{write_stdin}}, \code{\link{read_stdout}} and \code{\link{read_stderr}}
#' can then be used to communicate with the launched proces. \code{\link{status}} will
#' return information about the state of the stream object.
#' 
#' @author Timothy H. Keitt
#' @author Jonathan Wakeley (pstreams C++ library)
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
                   handle = "externalptr",
                   read_formatter = "function",
                   write_formatter = "function",
                   buffer_size = "numeric",
                   max_reads = "numeric"))

#' Open a pipe stream object
#'
#' Opens a set of pipes to stdin, stdout and stderr
#' on the specified process.
#' 
#' @param command the program to run
#' @param args a vector of argument strings
#' @param bufsz size of the read buffer
#' @param max_reads maximum number of buffer fills
#' @param read_formatter formatter function when reading
#' @param write_formatter formatter function when writing
#' 
#' @examples
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
#' close(x)
#' status(x)
#' 
#' wf = function(x) "dir()"
#' rf = function(x) "Boo!"
#' x = pstream("R", "--vanilla --slave", rf, wf)
#' write_stdin(x, "q()")
#' read_stdout(x)
#' close(x)
#' 
#' @rdname pstream
#' @export
pstream = function(command, args = "",
                   read_formatter = function(x) x,
                   write_formatter = function(x) as.character(x),
                   bufsz = 1024, max_reads = 1024)
{
  finalizer.fun = function(handle) close_(handle)
  argv = if(nzchar(args)) c(command, args) else NULL
  s = make_pstream(command, argv)
  if (!is_open_(s)) stop("Could not open stream")
  reg.finalizer(s, finalizer.fun, TRUE)
  new("pstream",
      command = command,
      args = args,
      handle = s,
      buffer_size = bufsz,
      max_reads = max_reads,
      read_formatter = read_formatter,
      write_formatter = write_formatter)
}

#' @param func a formatter function
#' @rdname pstream
#' @export
set_read_formatter = function(stream, func) stream@read_formatter = func

#' @rdname pstream
#' @export
set_write_formatter = function(stream, func) stream@write_formatter = func

#' @rdname pstream
#' @export
set_buffer_size = function(stream, bufsz) stream@buffer_size = bufsz

#' @rdname pstream
#' @export
set_max_reads = function(stream, max_reads) stream@max_reads = max_reads

#' @param stream a pstream object
#' @param wait number of seconds to wait before sending the kill signal
#' @details Closing a stream will wait until the spawned process completes. This
#' can hang your session if the process is not well-behaved. You should manually
#' end the proces if possible. \code{pstream_close} will check whether the program
#' has exited. If it is still running, EOF is sent. The process is then
#' checked for \code{wait} seconds.
#' If the process does not exit during that period, then SIGTERM signal is sent. If
#' after another round of waiting, the process has not existed, it is then sent
#' the SIGKILL signal. After that, the stream is manually closed.
#' 
#' @rdname pstream
#' @export
pstream_close = function(stream, wait = 10)
{
  close_(stream@handle, wait = wait)
}

#' @note Pipe stream objects are not compatible with R \code{\link{connection}}
#' objects. (See \code{\link{pstream_input_con}}.) However, \code{\link{open}}
#' and \code{\link{close}} methods are defined for convenience.
#' \code{close} calls \code{pstream_close}. \code{open} will
#' reopen a closed pstream object.
#' @param con a pstream object
#' @param ... ignored
#' @rdname pstream
#' @export
close.pstream = function(con, ...)
{
  close_(con@handle, ...)
  invisible(con)
}

#' @rdname pstream
#' @export
open.pstream = function(con, ...)
{
  args = con@args
  command = con@command
  finalizer.fun = function(handle) close_(handle)
  argv = if(nzchar(args)) c(command, args) else NULL
  s = make_pstream(command, argv)
  con@handle = s
  return(con)
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
  cat("command:", object@command, object@args, "\n")
  if (has_exited(x))
  {
    cat("Process terminated and returned code", exit_code(object), "\n")
    cat(read_stderr(x, 0))
  }
})

#' Read and write data to process
#' 
#' @param stream a pstream object
#' @param data a vector of values
#' @param send_endl if true, write return to stream
#' @param send_eof if true, write EOF to stream
#' @param timeout number of second to atempt reading
#' 
#' @details
#' Because reading from the pipe stream is non-blocking, there is
#' no method to determine whether the process has written anything
#' to its standard out or standard error. As a result,
#' \code{read_stdout} and \code{read_stderr} may return empty strings
#' indicating the process has not generated any output. These two read
#' functions take a timeout parameter that sets the amount of time in
#' seconds to attempt reading. If any output is available for consumption
#' during this period, then these functions will continue to read output
#' until all available output is consumed or the number of read exceeds the
#' \code{max_reads} parameter. This output is then returned.
#' A slight pause is necessary between attempts to consume output from
#' the process. This delay is controlled by the compile-time parameter
#' TICK_DELAY, which is in units of miliseconds. Ten miliseconds appears
#' to be sufficient to avoid starvation of the input buffer. A longer
#' delay will be less likely to return partial output
#' and will be more CPU efficient. A shorter delay will lead to less
#' latency.
#' 
#' @examples
#' x = pstream("R")
#' read_stderr(x)
#' 
#' x = pstream("R", "--vanilla")
#' read_stdout(x)
#' write_stdin(x, "R.Version()")
#' read_stdout(x)
#' write_stdin(x, "q()")
#' x = pstream("R", "--vanilla --slave")
#' system.time(read_stdout(x, 1))
#' system.time(read_stdout(x, 2))
#' system.time(read_stdout(x, 3))
#' write_stdin(x, "R.Version()")
#' system.time(read_stdout(x, 100))
#' pstream_close(x)
#' 
#' @rdname read-write
#' @export
write_stdin = function(stream, data,
                       send_endl = TRUE,
                       send_eof = FALSE)
{
  wrf = stream@write_formatter
  for (val in unlist(data))
    write_stdin_(stream@handle, wrf(val), send_endl)
  if (send_eof) send_eof_(stream@handle)
  return(invisible(stream))
}

#' @rdname read-write
#' @export
read_stdout = function(stream, timeout = 1)
{
  rdf = stream@read_formatter
  res = rdf(read_stdout_(stream@handle, timeout,
                         stream@buffer_size, stream@max_reads))
  class(res) = "rawtext"
  return(res)
}

#' @rdname read-write
#' @export
read_stderr = function(stream, timeout = 1,
                       bufsz = 1024, max_reads = 1024)
{
  rdf = stream@read_formatter
  res = rdf(read_stderr_(stream@handle, timeout,
                         stream@buffer_size, stream@max_reads))
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
#' @param con a pstream connection object
#' 
#' @details
#' R's \code{\link{connections}} objects provide uniform access to a variety
#' of IO modes. These function build \code{\link{textConnection}} object that
#' read or write to a pstream. An input connection simply reads from stdout,
#' or optionally stderr, and then returns that text when the connection is
#' read. Note that the reading happens at the time of creation.
#' 
#' You must call \code{\link{flush}} on an output connection or nothing
#' will get written to the processes standard input. Because these objects
#' are \code{\link{textConnection}}s, they cannot be used repeatedly.
#' Always initialize a new connection for each use.
#' 
#' @return a \code{\link{textConnection}} object
#' 
#' @examples
#' x = pstream("R", "--vanilla --slave")
#' c1 = pstream_output_con(x)
#' writeLines("R.Version()", c1)
#' flush(c1)                # required
#' c2 = pstream_input_con(x)
#' cat(readLines(c2))
#' pstream_close(x)
#' 
#' x = pstream("R", "--vanilla --slave")
#' a = 1:3
#' x %<<% "a = unserialize(stdin())"
#' c1 = pstream_output_con(x)
#' serialize(a, c1)
#' flush(c1)                   # required
#' x %<<% "serialize(a, stdout())"
#' c2 = pstream_input_con(x)
#' cat(unserialize(c2))
#' pstream_close(x)
#' 
#' @rdname pstream-con
#' @export
pstream_input_con = function(stream, timeout = 5, stderr = FALSE)
{
  msg = if (stderr) read_stderr(stream, timeout)
               else read_stdout(stream, timeout)
  textConnection(msg)
}

#' @rdname pstream-con
#' @export
pstream_output_con = function(stream, send_eof = FALSE)
{
  msg = NULL
  tcon = textConnection("msg", open = "w", local = TRUE)
  class(tcon) = c("pstream_output_con", class(tcon))
  attr(tcon, "flush") = function() write_stdin(stream, msg, send_eof)
  return(tcon)
}

setClass("pstream_output_con")

#' @rdname pstream-con
#' @export
setMethod("flush",
signature(con = "pstream_output_con"),
function(con) {f = attr(con, "flush"); f()})

#' Infix stream operators
#' 
#' @param lhs a pstream object
#' @param rhs a data value or name
#' 
#' @details
#' The \code{\%<<\%} operator writes the object on the right-hand
#' side to the pstream object on the left-hand side using
#' \code{\link{write_stdin}}. The \code{\%>>\%} opertor reads from
#' the pstream object on the left-hand side and stores the result
#' in the variable on the right-hand side using \code{\link{read_stdout}}.
#' The \code{\%<>\%} writes a string to the stream and immediately
#' reads from standard output and returns the result. This is mostly
#' for quickly viewing the output from a program.
#' 
#' @return a pstream object invisibly
#' 
#' @examples
#' x = pstream("R", "--vanilla --slave")
#' x %<<% "R.Version()"
#' x %>>% y
#' show(y)
#' x %<<% "R.Version()" %<<% "dir()" %>>% y
#' show(y)
#' x %<>% "R.Version()"
#' 
#' @rdname stream-infix
#' @export
`%<<%` = function(lhs, rhs)
{
  write_stdin(lhs, rhs)
  invisible(lhs)
}

#' @rdname stream-infix
#' @export
`%>>%` = function(lhs, rhs)
{
  nm = deparse(substitute(rhs))
  x = read_stdout(lhs)
  assign(nm, x, 1)
  invisible(lhs)
}

#' @rdname stream-infix
#' @export
`%<>%` = function(lhs, rhs)
{
  write_stdin(lhs, rhs)
  if (has_exited(lhs))
    read_stderr(lhs)
  else
   read_stdout(lhs)
}

