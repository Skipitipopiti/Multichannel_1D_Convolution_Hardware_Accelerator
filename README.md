**Hardware Accelerator for Multichannel 1D Convolution**

A high-performance, fully synthesizable SystemVerilog RTL design of a multichannel 1D convolution hardware accelerator designed for integration within a RISC-V SoC architecture.

This core is optimized for demanding edge-computing scenarios, targeting applications like real-time audio processing, biomedical signal analysis (ECG/EEG), and localized structural health monitoring.

**🚀 Key Features**
Pipelined Datapath & High Throughput: Built upon 4 parallel Multiply-Accumulate (MAC) units working in tandem with 4 Serial-Input Parallel-Output (SIPO) shift registers operating as a hardware sliding-window. This structure maximizes data reuse and achieved a ~62x speedup compared to bare-metal software execution.

Aggressive Memory Optimization: Engineered around a custom hardware tiling strategy specifically tailored to process large datasets within severe memory constraints (512B Scratchpad Memory).

Autonomous Data Alignment: Features completely hardwired, zero-overhead zero-padding logic to handle convolution boundary conditions natively in the datapath without requiring CPU intervention.

Standard HW/SW Interface: Integrated via Memory-Mapped Control and Status Registers (CSRs) over an Open Bus Interface (OBI). System synchronization and cross-domain data transfers are fully secured through a robust, interlocked 4-phase handshake protocol.
