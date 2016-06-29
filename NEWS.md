# vicar 0.1.1

* Added `vruv2`, a variance-inflated version of RUV2.
* The main function for variance-inflated RUV4 is now `vruv4`. I though that `vicarius_ruv4` was too verbose. In the future, as I create new calibrated versions of confounder adjustment methods, the function name will just have a "v" in front of the name of the confounder adjustment method.
* `vruv4` no longer works when `k = 0`. I plan on adding a separate function for variance inflation without confounder adjustment.
* `limmashrink = TRUE` is now the default.