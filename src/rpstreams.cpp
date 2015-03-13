#include "../inst/include/rpstreams.h"

// Use R for more protability
static Function rsleep("Sys.sleep");

// [[Rcpp::export]]
handle
make_pstream(std::string command, SEXP args)
{
    if (Rf_isNull(args))
      return handle(new pstream(command, mode));
    argvec argv = as<argvec>(args);
    return handle(new pstream(command, argv, mode));
}

static bool still_running(handle s)
{
  for (int i = 0; i != KILL_WAIT_SECONDS; ++i)
  {
    if (s->rdbuf()->exited()) return false;
    sleep(1);
  }
  return !s->rdbuf()->exited();
}

// [[Rcpp::export]]
void close_(handle s)
{
  if (!s) stop("Invalid stream reference");
  if (!s->rdbuf()->exited()) s->rdbuf()->peof();
  if (still_running(s)) s->rdbuf()->killpg(15);
  if (still_running(s)) s->rdbuf()->killpg(9);
  if (s->is_open()) s->close();
}

// [[Rcpp::export]]
void write_stdin_(handle s, std::string v)
{
  if (!s) stop("Invalid stream reference");
  *s << v << std::endl;
}

// [[Rcpp::export]]
std::string read_stdout_(handle s, double timeout = 0)
{
  if (!s) stop("Invalid stream reference");
  char buf[1024];
  int n;
  std::stringstream ss;
  std::time_t start = std::time(NULL);
  while (true)
  {
    n = s->out().readsome(buf, sizeof(buf));
    if (n != 0)
    {
      ss.write(buf, n);
      while (true)
      {
        usleep(TICK_DELAY);
        n = s->out().readsome(buf, sizeof(buf));
        if (n != 0) ss.write(buf, n); else break;
      }
      break;
    }
    std::time_t now = std::time(NULL);
    if (difftime(now, start) > timeout) break;
  }
  return ss.str();
}

// [[Rcpp::export]]
std::string read_stderr_(handle s, double timeout = 0)
{
  if (!s) stop("Invalid stream reference");
  char buf[1024];
  int n;
  std::stringstream ss;
  std::time_t start = std::time(NULL);
  while (true)
  {
    n = s->err().readsome(buf, sizeof(buf));
    if (n != 0)
    {
      ss.write(buf, n);
      while (true)
      {
        usleep(TICK_DELAY);
        n = s->err().readsome(buf, sizeof(buf));
        if (n != 0) ss.write(buf, n); else break;
      }
      break;
    }
    std::time_t now = std::time(NULL);
    if (difftime(now, start) > timeout) break;
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
