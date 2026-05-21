# Hardware Accelerator for Multichannel 1D Convolution

A high-performance, fully synthesizable **SystemVerilog RTL** hardware accelerator designed for seamless integration within a RISC-V SoC architecture. 

This core is purpose-built for low-latency, resource-constrained edge-computing scenarios, targeting application domains such as real-time audio processing, biomedical signal analysis (ECG/EEG), and localized structural health monitoring.

---

## 🚀 Key Features

* **High-Throughput Pipelined Datapath:** Driven by an array of **4 parallel MAC (Multiply-Accumulate) units** paired with **4 SIPO (Serial-Input Parallel-Output) shift registers** implementing a hardware-level sliding window. This architecture maximizes data reuse and delivers a **~62x speedup** over bare-metal software execution.
* **Aggressive Memory Optimization:** Architected around a custom hardware tiling strategy specifically tailored to stream and process large datasets under severe hardware constraints (**512B Scratchpad SRAM**).
* **Zero-Overhead Data Alignment:** Features fully hardwired, autonomous zero-padding logic that natively handles convolution boundary conditions directly within the datapath, completely offloading the host CPU.
* **Standard HW/SW Interface:** Integrated via Memory-Mapped Control and Status Registers (CSRs) over an **OBI (Open Bus Interface)**. System synchronization and data handoff are secured by a robust, fully interlocked **4-phase handshake protocol**.
