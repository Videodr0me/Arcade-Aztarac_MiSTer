# T80 sound CPU

Native VHDL from
[MiSTer-devel/ZX-Spectrum_MISTer](https://github.com/MiSTer-devel/ZX-Spectrum_MISTer/tree/a5585ec537badad960bf82473bc52983f4bba5fc/rtl/T80),
revision `a5585ec537badad960bf82473bc52983f4bba5fc`.

Aztarac uses T80s in Z80 mode with T2 writes, standard I/O timing and OUT0=0,
at the original 2 MHz enable rate. The QIP is the local Quartus source list.
The upstream license notices are retained.

Videodr0me fixed flag bits 3 and 5 for the Z80's SCF and CCF instructions
by tracking writes to the flags, even when their values stay the same. POP AF and
EX AF,AF' do not count as flag-writing instructions; DD/FD prefix fetches clear
the history. Instruction sequencing and bus timing are unchanged. The other
five VHDL files retain their upstream contents.
