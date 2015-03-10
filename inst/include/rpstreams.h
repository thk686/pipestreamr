#ifndef __RPSTREAMS_H__
#define __RPSTREAMS_H__
#include <sstream>
#include "pstream.h"
using namespace redi;
#include <Rcpp.h>
using namespace Rcpp;
static const pstreams::pmode mode =
  pstreams::pstdin|pstreams::pstdout|pstreams::pstderr;
typedef XPtr<pstream> handle;
typedef std::vector<std::string> argvec;
#endif //  __RPSTREAMS_H__