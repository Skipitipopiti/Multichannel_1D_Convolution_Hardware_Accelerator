// Copyright 2024 Politecnico di Torino.
// Copyright and related rights are licensed under the Solderpad Hardware
// License, Version 2.0 (the "License"); you may not use this file except in
// compliance with the License. You may obtain a copy of the License at
// http://solderpad.org/licenses/SHL-2.0. Unless required by applicable law
// or agreed to in writing, software, hardware and materials distributed under
// this License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
// CONDITIONS OF ANY KIND, either express or implied. See the License for the
// specific language governing permissions and limitations under the License.
//
// File: conv1d.cpp
// Author(s):
//   Luigi Giuffrida
// Date: 08/11/2024
// Description: TB for the OBI CONV1D accelerator

#include <iostream>
#include <getopt.h>
#include <random>
#include <time.h>

// Verilator libraries
#include <verilated.h>
#include <verilated_fst_c.h>

// DUT header
#include "Vconv1d_tb_wrapper.h"
#include "conv1d_control_reg.h"

// Testbench components
#include "tb_macros.hh"
#include "tb_components.hh"

// Test data
#include "data.h"

// Defines
// -------
#define FST_FILENAME "logs/waves.fst"
#define END_OF_RESET_TIME 5
#define MAX_SIM_CYCLES 2e6
#define MAX_SIM_TIME (MAX_SIM_CYCLES * 2)
#define WATCHDOG_TIMEOUT 1000   // cycles to wait for a program step to complete
#define END_OF_TEST_TIMEOUT 10 // cycles between done assertion and simulation end

#define K_SIZE 320 // 80*4
#define S_SIZE 128 // 32*4
#define O_SIZE 64  // 16*4
#define P_SIZE 32  // 8*4

// Generate clock and reset
void clkGen(Vconv1d_tb_wrapper *dut);
void rstDut(Vconv1d_tb_wrapper *dut, vluint64_t sim_time);

// Generate OBI transactions
ObiReqTx *genObiWriteReqTx(const vluint32_t addr_offs, const vluint32_t wdata, vluint8_t be);
ObiReqTx *genObiReadReqTx(const vluint32_t addr_offs);
RegReqTx *genRegWriteReqTx(const vluint32_t addr_offs, const vluint32_t wdata, vluint8_t wstrb);
RegReqTx *genRegReadReqTx(const vluint32_t addr_offs);

// Run a number of cycles
void runCycles(unsigned int ncycles, Vconv1d_tb_wrapper *dut, uint8_t gen_waves, VerilatedFstC *trace);

// Global variables
vluint64_t sim_cycles = 0;
TbLogger logger; // testbench logger

// -------------------------------------------------------------------------
// REGISTER MAP & MASKS   donr by leo
// -------------------------------------------------------------------------
// Indirizzi dei Registri (Offset)
enum RegMap
{
    REG_CTRL = 0x00,  // Controllo (Scrittura)
    REG_STATUS = 0x04 // Stato (Lettura)
};

// Maschere e Comandi
enum RegBits
{
    // Registro CONTROL
    CMD_START = 0x01,     // Bit 0: Start
    CMD_RESET_ACK = 0x00, // Bit 0: Reset Acknowledge (da TB)

    // Registro STATUS
    STS_RUNNING = 0x01,  // Bit 0: Running
    STS_DONE = 0x02,      // Bit 1: Done
    STS_OUT_READY = 0x04, // Bit 2: Output Ready
    STS_ACK = 0x04,   // Bit 2: Acknowledge (da TB)
    STS_PAD_READY = 0x08, // Bit 3: Pad Ready
    STS_S_REQ = 0x10,     // Bit 4: Samples Request
    STS_K_REQ = 0x20     // Bit 5: Kernel Request
};

enum MemMap
{
    MEM_INPUT = 0x00,  // Input starts at offset
    MEM_K = 0x80,      // Weights start at offset
    MEM_OUTPUT = 0x320 // Output starts at offset
};

int main(int argc, char *argv[])
{
    // Define command-line options
    const option longopts[] = {
        {"log_level", required_argument, NULL, 'l'},
        {"gen_waves", required_argument, NULL, 'w'},
        {"seed", required_argument, NULL, 's'},
        {NULL, 0, NULL, 0}};

    // Process command-line options
    // ----------------------------
    int opt; // current option
    int prg_seed = time(NULL);
    bool gen_waves = true;
    while ((opt = getopt_long(argc, argv, "l:w:", longopts, NULL)) >= 0)
    {
        switch (opt)
        {
        case 'l': // set the log level
            logger.setLogLvl(optarg);
            TB_CONFIG("Log level set to %s", optarg);
            break;
        case 'w': // generate waves
            if (!strcmp(optarg, "true"))
            {
                gen_waves = 1;
                TB_CONFIG("Waves enabled");
            }
            else
            {
                gen_waves = 0;
                TB_CONFIG("Waves disabled");
            }
            break;
        case 's': // set the seed
            prg_seed = atoi(optarg);
            TB_CONFIG("Seed set to %d", prg_seed);
            break;
        default:
            TB_ERR("ERROR: unrecognised option %c.\n", opt);
            exit(EXIT_FAILURE);
        }
    }

    // Create Verilator simulation context
    VerilatedContext *cntx = new VerilatedContext;

    // Pass simulation context to the logger
    logger.setSimContext(cntx);

    if (gen_waves)
    {
        Verilated::mkdir("logs");
        cntx->traceEverOn(true);
    }

    // Instantiate DUT
    Vconv1d_tb_wrapper *dut = new Vconv1d_tb_wrapper(cntx);

    // Set the file to store the waveforms in
    VerilatedFstC *trace = NULL;
    if (gen_waves)
    {
        trace = new VerilatedFstC;
        dut->trace(trace, 10);
        trace->open(FST_FILENAME);
    }

    // TB components
    Drv *drv = new Drv(dut);
    Scb *scb = new Scb();
    ReqMonitor *reqMon = new ReqMonitor(dut, scb);
    RspMonitor *rspMon = new RspMonitor(dut, scb);

    // Initialize PRG
    srand(prg_seed);

    // Simulation program
    // ------------------
    // TODO: Define simulation program variables
    ObiReqTx *obi_req = NULL;
    vluint32_t obi_rdata = 0;
    uint32_t obi_data = 0;
    uint32_t obi_addr_s = 0;
    uint32_t obi_addr_k = 0;
    uint32_t obi_addr_pad = 0;
    uint32_t obi_addr_out = 2;
    unsigned int data_size = 0;
    bool obi_accepted = 0;

    uint32_t add_SP_s = 0;
    uint32_t add_SP_k = 0;
    uint32_t add_SP_pad = 0;
    uint32_t add_SP_out = 0;

    RegReqTx *reg_read = NULL;
    RegReqTx *reg_req = NULL;
    vluint32_t reg_rdata = 0;
    bool reg_accepted = 0;
    bool ack_flag = 0;

    bool irq_received = 0;

    bool form_s = 0, form_pad = 0; // 0 => form s ; 1=> form sp
    uint32_t row_s = 0, row_pad = 0, row_out = 0;
    uint32_t col_s = 0, col_pad = 0, col_out = 0;
    uint32_t k_s = 0, cin_s = 0;
    uint32_t block_s = 0, block_out = 0;
    uint32_t cout_pad = 0, cout_out = 0;
    uint32_t pad_offset = 0;
    uint32_t k_cnt = 0;
    bool k_offset_en = 0;
    uint32_t wdata = 0;
    uint8_t byte = 0;
    uint32_t sh = 0;
    uint32_t sh_k = 3;

    uint32_t be = 0x8;
    uint32_t be_cnt = 0;   

    bool end_of_test = false;
    unsigned int exit_timer = 0;
    unsigned int watchdog = 0;
    unsigned int prev_step_cnt = 0;
    unsigned int step_cnt = 0;

    TB_LOG(LOG_LOW, "Starting simulation...");
    while (!cntx->gotFinish() && cntx->time() < MAX_SIM_TIME)
    {
        // Generate clock and reset
        rstDut(dut, cntx->time());
        clkGen(dut);

        // Evaluate simulation step
        dut->eval();

        if (dut->clk_i == 1 && cntx->time() > END_OF_RESET_TIME)
        {
            // TB_LOG(LOG_LOW, "Cycle %d - clk_i=%d, rst_ni=%d, time=%d, step=%d", sim_cycles, dut->clk_i, dut->rst_ni, cntx->time(), step_cnt);
            switch (step_cnt)
            {
            // Give Start
            case 0:
                if (!reg_accepted)
                {
                    TB_LOG(LOG_HIGH, "0 - Starting the accelerator...");
                    // Scrive 1 nel registro CONTROL
                    reg_req = genRegWriteReqTx(REG_CTRL, CMD_START, 0xF); // START command: set bit 0 to 1
                    break;
                }
                reg_accepted = false;
                step_cnt = 1; // Vai al Polling
                break;

            // First ack reset
            case 1:
                if (!reg_accepted)
                {
                    reg_req = genRegWriteReqTx(REG_CTRL, 0x00, 0xF);
                    TB_LOG(LOG_HIGH, "1 - Resetting acks...");
                    break;
                }
                reg_accepted = false;
                step_cnt = 2; // Vai al Polling
                break;

            case 2: // Polling di status reg
                if (!reg_accepted)
                {
                    reg_req = genRegReadReqTx(REG_STATUS);
                    TB_LOG(LOG_HIGH, "2 - Reading status regs...");
                    break;
                }
                reg_accepted = false;

                TB_LOG(LOG_HIGH, "Status register read: '%x'", reg_rdata);

                if (reg_rdata & STS_S_REQ)
                {
                    step_cnt = 4;
                    TB_LOG(LOG_LOW, " -> Samples request received: go to step 4");
                }
                else if (reg_rdata & STS_K_REQ)
                {
                    step_cnt = 3;
                    TB_LOG(LOG_LOW, " -> Kernel request received: go to step 3");
                }
                else if (reg_rdata & STS_OUT_READY)
                {
                    step_cnt = 6;
                    TB_LOG(LOG_LOW, " -> Out ready received: go to step 6");
                }
                else if (reg_rdata & STS_PAD_READY)
                {
                    step_cnt = 5;
                    TB_LOG(LOG_LOW, " -> Pad ready received: go to step 5");
                }
                else if (reg_rdata & STS_DONE)
                {
                    TB_LOG(LOG_LOW, " -> DONE bit detected! You fucking made it!");
                    end_of_test = true;
                }
                else
                {
                    // Nessun flag attivo interessante.
                    // Rimaniamo nel case 1 e riproviamo a leggere al prossimo giro.
                    step_cnt = 1;
                }
                break;


            //------------------------------- k request handling -------------------------------
            case 3:
                TB_LOG(LOG_LOW, "Step 3: k request handling...");
                if (!obi_accepted) {
                    obi_data = *((uint32_t *)(&F[k_offset_en*80*4 + obi_addr_k]));

                    byte = (obi_data >> (8*k_cnt)) & 0xff;
                    obi_data = byte;
                    obi_data = obi_data << (8*sh_k);

                    TB_LOG(LOG_LOW, "Writing WEIGHT '%x' from MM address '%d' to SP address '%d'", obi_data, obi_addr_k + k_cnt, 32 + add_SP_k);
                    obi_req = genObiWriteReqTx(32*4 + add_SP_k*4, obi_data, be); // !!!
                    break;
                }

                obi_accepted = false;

                // next address computation
                k_cnt++;
                add_SP_k++;
                if (k_cnt == 4) {
                    k_cnt = 0;
                    obi_addr_k += 4;
                }
                
                if (add_SP_k == 80) {
                    sh_k--;
                    be = be >> 1; // shift be for the next 4 weights in the same block
                    add_SP_k = 0; 
                }

                if (obi_addr_k == 80*4) {
                    sh_k = 3;
                    obi_addr_k = 0;
                    be = 0xf;
                    k_offset_en = !k_offset_en;
                    TB_LOG(LOG_LOW, "All kernels sent...");
                    step_cnt = 7; // restart handling
                }
                break;

            
            
            //------------------------------- s request handling -------------------------------
            case 4:  
                TB_LOG(LOG_LOW, "Step 4: s request handling...");
                if (!obi_accepted) {
                    obi_data = *((uint32_t *)(&A[obi_addr_s]));

                    if(form_s) {
                        be = 0x1 << sh;

                        byte = (obi_data >> (8*k_s)) & 0xff;
                        obi_data = uint32_t(byte) << (8*sh);
                    } else
                        be = 0xf;

                    TB_LOG(LOG_LOW, "MM address: row = %d; cin = %d; col = %d; block = %d; k = %d\n obi_addr_s = %d", row_s, cin_s, col_s, block_s, k_s, obi_addr_s);
                    TB_LOG(LOG_LOW, "Writing SAMPLE '%x' from MM address '%d' to SP address '%d'", obi_data, obi_addr_s, add_SP_s);
                    obi_req = genObiWriteReqTx(4*add_SP_s, obi_data, be);
                    break;
                }

                obi_accepted = false;                

                // next obi address computation

                if (!form_s) // forma s
                { 
                    add_SP_s++;
                    row_s++;
                    if (row_s == 4)
                    {
                        row_s = 0;
                        col_s = 1;
                        form_s = 1; // passiamo alla forma sp
                        //be = 0x8; // reset be at the beginning of each block of samples
                    }
                }
                else // forma sp
                { 
                    k_s++;
                    add_SP_s++;
                    if (k_s == 4)
                    {
                        add_SP_s -= 4; // torniamo all'inizio del blocco di samples da cui stiamo leggendo, per poi passare al blocco successivo
                        k_s = 0;
                        row_s++;
                        sh++;
                        if (row_s == 4)
                        {
                            row_s = 0;
                            cin_s++;
                            form_s = 0; // passiamo alla forma s
                            sh = 0;
                            add_SP_s += 4;
                            col_s = 0;
                            if (cin_s == 4)
                            {
                                cin_s = 0;
                            }
                        }
                    }
                }

                if (add_SP_s == 32) {
                    add_SP_s = 0;
                    row_s = 0;

                    TB_LOG(LOG_LOW, "All samples sent...");
                    step_cnt = 7; // restart handling

                    block_s++;
                    if (block_s == 31) {
                        block_s = 0;
                    }
                }

                // calcolo per forma
                obi_addr_s = 128*row_s + cin_s*(4*128) + col_s*4 + block_s*4;
                break;

            
            
            //------------------------------- pad requests handling -------------------------------
            case 5:    
                TB_LOG(LOG_LOW, "Step 5: pad request handling...");
                if (!obi_accepted) {

                    if (!form_pad)// input padding
                        pad_offset = 0;
                    else // output padding
                        pad_offset = 126; 

                    TB_LOG(LOG_MEDIUM, "PADDING OUTPUT from MM address '%d' = %d + %d + %d*128 + %d*128*4", obi_addr_pad, pad_offset, col_pad, row_pad, cout_pad);
                    obi_data = *((uint32_t *)(&R[pad_offset+obi_addr_pad]));
                    TB_LOG(LOG_MEDIUM, "Comparing  Sample '%x' from MM address '%d' to SP address '%d'", obi_data, pad_offset+obi_addr_pad, 112 + add_SP_pad);
                    obi_req = genObiReadReqTx(112*4 + add_SP_pad*4);
                    break;
                }
                obi_accepted = false;

                scb->scheduleObiCheck(obi_data);

                /*for (const auto& val : scb->obi_exp_q) {
                    TB_LOG(LOG_HIGH, "Expected value in SCB queue: 0x%08x", val);
                }*/

                // next obi address computation
                
                row_pad++;
                if (row_pad == 4) {
                    row_pad = 0;
                    col_pad++;
                    if (col_pad == 2)
                        {
                            col_pad = 0;
                            if (form_pad)
                            {
                                form_pad = 0; // cambio forma
                                cout_pad++;
                                if (cout_pad == 2)
                                    {
                                        cout_pad = 0;
                                    }
                            }
                            else
                            {
                                form_pad = 1; // cambio forma
                            }
                        }
                    }
                
                add_SP_pad++;
                if (add_SP_pad == 8) {
                    add_SP_pad = 0;

                    TB_LOG(LOG_LOW, "All padding samples read...");
                    step_cnt = 7; // restart handling
                }

                obi_addr_pad = col_pad + row_pad * 128 + cout_pad * 128 * 4;

                break;
            

            //------------------------------- out request handling -------------------------------
            case 6:
                TB_LOG(LOG_LOW, "Step 6: out request handling...");
                if (!obi_accepted) {
                    obi_data = *((uint32_t *)(&R[obi_addr_out]));
                    TB_LOG(LOG_LOW, "Comparing  OUT '%x' from MM address '%x' with scratchpad from address '%d'", obi_data, obi_addr_out, 112 + add_SP_out);
                    obi_req = genObiReadReqTx(112*4 + add_SP_out*4);
                    break;
                }

                scb->scheduleObiCheck(obi_data);

                // next obi address computation
                row_out++;
                if (row_out == 4) {
                    row_out = 0;
                    col_out++;
                    if (col_out == 4) {
                        col_out = 0;
                        block_out++;
                        if (block_out == 31) {
                            block_out = 0;
                            cout_out++;
                            if (cout_out == 2) {
                                cout_out = 0;
                            }
                        }
                    }
                }

                add_SP_out++;
                if(add_SP_out == 16) {
                    add_SP_out = 0;

                    TB_LOG(LOG_LOW, "All output samples read!");
                    step_cnt = 7; // restart handling
                }

                obi_addr_out = 2 + col_out + row_out*128 + block_out*4 + cout_out*128*4;
                break;
            
            case 7: // restart handling
                if (!reg_accepted)
                {
                    reg_req = genRegWriteReqTx(REG_CTRL, STS_ACK, 0xf); // ACK K_REQ  1
                    TB_LOG(LOG_LOW, "Request solved");
                    break;
                }
                reg_accepted = false;
                step_cnt = 8;
                break;
            
            case 8: // deasserisco l'ack
                if (!reg_accepted)
                {
                    reg_req = genRegWriteReqTx(REG_CTRL, 0x00, 0xF); // ACK K_REQ 0
                    TB_LOG(LOG_LOW, "ACK deasserted");
                    break;
                }
                reg_accepted = false;
                step_cnt = 2; // torna al polling
                break;
             

            default:
                // Set simulation exit flag
                end_of_test = true;
                break;
            }

            // Drive DUT inputs
            drv->drive(obi_req, reg_req);
            delete obi_req;
            delete reg_req;
            obi_req = NULL;
            reg_req = NULL;

            // Update input signals
            dut->eval();

            // Monitor DUT signals
            reqMon->monitor();
            rspMon->monitor();

            irq_received = rspMon->irq();
            obi_accepted = reqMon->acceptedObi();
            reg_accepted = reqMon->acceptedReg();

            // Get register data (to be used in the test program above)
            if (reg_accepted)
            {
                reg_rdata = rspMon->getRegData();
            }
            if (rspMon->isDataReadyObi())
                obi_rdata = rspMon->getObiData();

            // Trigger scheduled checks
            if (scb->checkData() != 0)
                end_of_test = true;

            // Check for exit conditions
            if (prev_step_cnt != step_cnt)
                watchdog = 0;
            else
                watchdog++;
            if (watchdog > WATCHDOG_TIMEOUT)
            {
                TB_WARN("Watchdog timeout reached: terminating simulation.");
                scb->notifyError();
                break;
            }
            prev_step_cnt = step_cnt;
            if (end_of_test)
            {
                if (exit_timer++ == END_OF_TEST_TIMEOUT)
                {
                    TB_LOG(LOG_LOW, "End of simulation reached: terminating.");
                    break;
                }
            }
        }

        // Dump waveforms and advance simulation time
        if (gen_waves)
            trace->dump(cntx->time());
        if (dut->clk_i == 1)
            sim_cycles++;
        cntx->timeInc(1);
    }


    // Simulation complete
    dut->final();

    // Print simulation summary
    if (scb->getErrNum() > 0)
    {
        TB_ERR("CHECKS FAILED > errors: %u/%u", scb->getErrNum(), scb->getTxNum());
        if (gen_waves)
            trace->close();
        exit(EXIT_SUCCESS);
    }
    else if (!scb->isDone())
    {
        TB_ERR("CHECKS PENDING > errors: %u/%u", scb->getErrNum(), scb->getTxNum());
        if (gen_waves)
            trace->close();
        exit(EXIT_SUCCESS);
    }
    TB_SUCCESS(LOG_LOW, "CHECKS PASSED > errors: %u (checked %u transactions)", scb->getErrNum(), scb->getTxNum());

    // Clean up and exit
    if (gen_waves){
        trace->close();
        delete dut;
        delete cntx;
        delete obi_req;
        delete reg_req;

        return 0;
    }
}

void clkGen(Vconv1d_tb_wrapper *dut)
{
    dut->clk_i ^= 1;
}

void rstDut(Vconv1d_tb_wrapper *dut, vluint64_t sim_time)
{
    dut->rst_ni = 1;
    if (sim_time > 1 && sim_time < END_OF_RESET_TIME)
    {
        dut->rst_ni = 0;
    }
}

void runCycles(unsigned int ncycles, Vconv1d_tb_wrapper *dut, uint8_t gen_waves, VerilatedFstC *trace)
{
    VerilatedContext *cntx = dut->contextp();
    for (unsigned int i = 0; i < (2 * ncycles); i++)
    {
        // Generate clock
        clkGen(dut);

        // Evaluate the DUT
        dut->eval();

        // Save waveforms
        if (gen_waves)
            trace->dump(cntx->time());
        if (dut->clk_i == 1)
            sim_cycles++;
        cntx->timeInc(1);
    }
}

/* =========================================================================
 * HOW TO USE - OBI MEMORY INTERFACE (by Leo & Gemini :P)
 * =========================================================================
 *
 * Queste funzioni generano transazioni verso la MEMORIA (Scratchpad) dell'acceleratore.
 * Servono per caricare i dati (Input/Pesi) e leggere i risultati.
 * -------------------------------------------------------------------------
 * 1. SCRITTURA: genObiWriteReqTx(INDIRIZZO, DATO, MASCHERA)
 * -------------------------------------------------------------------------
 * Scrive una parola (32 bit) nella memoria interna dell'acceleratore.
 *
 * Parametri:
 * - addr_offs: Indirizzo in memoria (Byte address).
 * Es: 0x00 (Inizio Input), 0x80 (Inizio Pesi).
 * - wdata:     Il dato numerico da scrivere
 * - be:        Byte Enable (Maschera). Indica quali byte scrivere .
 * Usa sempre 0xF per scrivere 32 bit pieni.
 *
 * Esempio (Caricare un valore di input):
 * obi_req = genObiWriteReqTx(0x00, 1234, 0xF);
 *
 * -------------------------------------------------------------------------
 * 2. LETTURA: genObiReadReqTx(INDIRIZZO)
 * -------------------------------------------------------------------------
 * Legge una parola dalla memoria per verificare il risultato.
 * Il dato letto arriverà dopo qualche ciclo e verrà controllato dallo Scoreboard.
 *
 * Parametri:
 * - addr_offs: Indirizzo da leggere (es. 0x100 dove sta l'output).
 *
 * Esempio (Leggere un risultato per il check):
 * obi_req = genObiReadReqTx(0x100);
 * =========================================================================
 */

// Issue write OBI transaction
ObiReqTx *genObiWriteReqTx(const vluint32_t addr_offs, const vluint32_t wdata, vluint8_t be)
{
    ObiReqTx *req = new ObiReqTx;

    // OBI write request
    req->obi_req.req = 1;
    req->obi_req.we = 1;
    req->obi_req.be = be;
    req->obi_req.addr = addr_offs;
    req->obi_req.wdata = wdata;

    return req;
}

// Issue read OBI transaction
ObiReqTx *genObiReadReqTx(const vluint32_t addr_offs)
{
    ObiReqTx *req = new ObiReqTx;

    // OBI read request
    req->obi_req.req = 1;
    req->obi_req.we = 0;
    req->obi_req.be = 0xf;
    req->obi_req.addr = addr_offs;
    req->obi_req.wdata = 0;

    return req;
}

/* =========================================================================
 * HOW TO USE - REGISTER INTERFACE (by Leo & Gemini :P)
 * =========================================================================
 *
 * Queste funzioni generano transazioni sul bus di configurazione .
 * Servono per pilotare la Control Unit dell'acceleratore.
 *
 * -------------------------------------------------------------------------
 * 1. SCRITTURA: genRegWriteReqTx(INDIRIZZO, DATO, MASCHERA)
 * -------------------------------------------------------------------------
 * Invia un comando (es. Start) o configura un parametro.
 *
 * Parametri:
 * - addr_offs: Indirizzo del registro (es. REG_CTRL = 0x00).
 * - wdata:     Valore da scrivere (es. CMD_START = 1).
 * - wstrb:     Write Strobe (Maschera Byte). Usa sempre 0xF per scrivere 32 bit.
 *
 * Esempio (Dare lo START):
 * reg_req = genRegWriteReqTx(REG_CTRL, CMD_START, 0xF);
 *
 * -------------------------------------------------------------------------
 * 2. LETTURA: genRegReadReqTx(INDIRIZZO)
 * -------------------------------------------------------------------------
 * Richiede il valore corrente di un registro (es. per sapere se ha finito).
 * La risposta arriverà qualche ciclo dopo nel segnale 'reg_rdata'.
 *
 * Parametri:
 * - addr_offs: Indirizzo del registro da leggere (es. REG_STATUS = 0x04).
 *
 * Esempio (Leggere lo STATO):
 * reg_req = genRegReadReqTx(REG_STATUS);
 * =========================================================================
 */

// Issue write register interface transaction
RegReqTx *genRegWriteReqTx(const vluint32_t addr_offs, const vluint32_t wdata, vluint8_t wstrb)
{
    RegReqTx *req = new RegReqTx;

    // OBI write request
    req->reg_req.valid = 1;
    req->reg_req.write = 1;
    req->reg_req.wstrb = wstrb;
    req->reg_req.addr = addr_offs;
    req->reg_req.wdata = wdata;

    return req;
}

// Issue read register interface transaction
RegReqTx *genRegReadReqTx(const vluint32_t addr_offs)
{
    RegReqTx *req = new RegReqTx;

    // OBI read request
    req->reg_req.valid = 1;
    req->reg_req.write = 0;
    req->reg_req.wstrb = 0xf;
    req->reg_req.addr = addr_offs;
    req->reg_req.wdata = 0;

    return req;
}
