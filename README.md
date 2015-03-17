# rpstreams
An R library for bidirectional communication over pipes

This library wraps [pstreams](http://pstreams.sourceforge.net/).

You can use it to open a process, write to its standard input
and read from its standard output or standard error.

To install this package: `devtools::install_github("rpstreams", "thk686")`

Here is a small example:
```
x = pstream("tr", c("[:upper:]", "[:lower:]"))
x %<<.% "TEST" %>>% y
print(y)
close(x)

x = pstream("R", "--vanilla --slave")
a = 1:3
write_stdin(x, "a = unserialize(stdin())")
c1 = pstream_output_con(x)       # writes stdin
serialize(a, conn(c1))            # get the con object
flush(c1)                         # required
write_stdin(x, "serialize(a, stdout())")
c2 = pstream_input_con(x)        # reads stdout
unserialize(c2)
pstream_close(x)
```
