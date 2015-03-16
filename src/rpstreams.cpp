#include "../inst/include/rpstreams.h"

// [[Rcpp::export]]
handle
make_pstream(std::string command, SEXP args)
{
    if (Rf_isNull(args))
      return handle(new pstream(command, mode));
    argvec argv = as<argvec>(args);
    return handle(new pstream(command, argv, mode));
}

static bool still_running(handle s, double wait = 10)
{
  std::time_t start = std::time(NULL);
  while (true)
  {
    if (s->rdbuf()->exited()) return false;
    usleep(TICK_DELAY);
    std::time_t now = std::time(NULL);
    if (std::difftime(now, start) > wait) break;
  }
  return !s->rdbuf()->exited();
}

// [[Rcpp::export]]
void close_(handle s, double wait = 10)
{
  if (!s) stop("Invalid stream reference");
  if (!s->rdbuf()->exited()) s->rdbuf()->peof();
  if (still_running(s, wait)) s->rdbuf()->killpg(15);
  if (still_running(s, wait)) s->rdbuf()->killpg(9);
  if (s->is_open()) s->close();
}

// [[Rcpp::export]]
void write_stdin_(handle s, std::string v, bool write_endl = true)
{
  if (!s) stop("Invalid stream reference");
  *s << v;
  if (write_endl) *s << std::endl;
}

// [[Rcpp::export]]
std::string read_stdout_(handle s,
                         double timeout = 0,
                         std::size_t bufsz = 1024,
                         std::size_t max_reads = 1024)
{
  int n;
  char buf[bufsz];
  if (!s) stop("Invalid stream reference");
  std::time_t start = std::time(NULL);
  std::stringstream ss;
  while (true)
  {
    n = s->out().readsome(buf, sizeof(buf));
    if (n != 0)
    {
      ss.write(buf, n);
      for (int i = 0; i != max_reads - 1; ++i)
      {
        usleep(TICK_DELAY);
        n = s->out().readsome(buf, sizeof(buf));
        if (n != 0) ss.write(buf, n); else break;
      }
      break;
    }
    std::time_t now = std::time(NULL);
    if (std::difftime(now, start) > timeout) break;
    usleep(TICK_DELAY);
  }
  return ss.str();
}

// [[Rcpp::export]]
std::string read_stderr_(handle s,
                         double timeout = 0,
                         std::size_t bufsz = 1024,
                         std::size_t max_reads = 1024)
{
  int n;
  char buf[bufsz];
  if (!s) stop("Invalid stream reference");
  std::time_t start = std::time(NULL);
  std::stringstream ss;
  while (true)
  {
    n = s->out().readsome(buf, sizeof(buf));
    if (n != 0)
    {
      ss.write(buf, n);
      for (int i = 0; i != max_reads - 1; ++i)
      {
        usleep(TICK_DELAY);
        n = s->err().readsome(buf, sizeof(buf));
        if (n != 0) ss.write(buf, n); else break;
      }
      break;
    }
    std::time_t now = std::time(NULL);
    if (std::difftime(now, start) > timeout) break;
    usleep(TICK_DELAY);
  }
  return ss.str();
}

// [[Rcpp::export]]
bool is_open_(handle s)
{
  if (!s) stop("Invalid stream reference");
  return s->is_open();
}

// [[Rcpp::export]]
bool is_eof_(handle s)
{
  if (!s) stop("Invalid stream reference");
  return s->eof();
}

// [[Rcpp::export]]
bool is_good_(handle s)
{
  if (!s) stop("Invalid stream reference");
  return s->good();
}

// [[Rcpp::export]]
bool is_bad_(handle s)
{
  if (!s) stop("Invalid stream reference");
  return s->bad();
}

// [[Rcpp::export]]
bool is_fail_(handle s)
{
  if (!s) stop("Invalid stream reference");
  return s->fail();
}

// [[Rcpp::export]]
void send_eof_(handle s)
{
  if (!s) stop("Invalid stream reference");
  s->rdbuf()->peof();
}

// [[Rcpp::export]]
int exit_code_(handle s)
{
  if (!s) stop("Invalid stream reference");
  return s->rdbuf()->status();  
}

// [[Rcpp::export]]
int errno_(handle s)
{
  if (!s) stop("Invalid stream reference");
  return s->rdbuf()->error();  
}

// [[Rcpp::export]]
bool has_exited_(handle s)
{
  if (!s) stop("Invalid stream reference");
  return s->rdbuf()->exited();  
}

// [[Rcpp::export]]
void signal_(handle s, int signal, bool group = false)
{
  if (!s) stop("Invalid stream reference");
  if (group)
    s->rdbuf()->killpg(signal);
  else
    s->rdbuf()->kill(signal);
}
