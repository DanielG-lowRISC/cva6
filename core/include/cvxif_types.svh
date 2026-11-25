`ifndef CVXIF_TYPES_SVH
`define CVXIF_TYPES_SVH

//CVXIF
`define READREGFLAGS_T(Cfg) logic [Cfg.X_NUM_RS+Cfg.X_DUALREAD-1:0]
`define WRITEREGFLAGS_T(Cfg) logic [Cfg.X_DUALWRITE:0]
`define ID_T(Cfg) logic [Cfg.X_ID_WIDTH-1:0]
`define HARTID_T(Cfg) logic [Cfg.X_HARTID_WIDTH-1:0]

`define X_COMPRESSED_REQ_T(Cfg, hartid_t) struct packed { \
    logic [15:0] instr; /*Offloaded compressed instruction*/ \
    hartid_t     hartid;  /*Identification of the hart offloading the instruction*/ \
}
`define X_COMPRESSED_RESP_T(Cfg) struct packed { \
    logic [31:0] instr; /*Uncompressed instruction*/ \
    logic accept; /*Is the offloaded compressed instruction (id) accepted by the coprocessor?*/ \
}

`define X_ISSUE_REQ_T(Cfg, hartid_t, id_t) struct packed { \
    logic [31:0] instr; /*Offloaded instruction*/ \
    hartid_t hartid; /*Identification of the hart offloading the instruction*/ \
    id_t id; /*Identification of the offloaded instruction*/ \
}
`define X_ISSUE_RESP_T(Cfg, writeregflags_t, readregflags_t) struct packed { \
    logic accept; /*Is the offloaded instruction (id) accepted by the coprocessor?*/ \
    writeregflags_t writeback; /*Will the coprocessor perform a writeback in the core to rd?*/ \
    readregflags_t register_read; /*Will the coprocessor perform require specific registers to be read?*/ \
    logic loadstore; /*Will the coprocessor perform memory transactions for this instruction?*/ \
}

// Memory (request/response) interface.
// Deviation from the specification: addr is XLEN wide instead of 32 bits so an
// RV64 virtual address fits.
`define X_MEM_REQ_T(Cfg) struct packed { \
    logic [Cfg.X_HARTID_WIDTH-1:0] hartid; /*Identification of the hart offloading the instruction*/ \
    logic [Cfg.X_ID_WIDTH-1:0]     id; /*Identification of the offloaded instruction*/ \
    logic [Cfg.XLEN-1:0]           addr; /*Virtual byte address of the memory transaction*/ \
    logic [1:0]                    mode; /*Effective privilege level*/ \
    logic                          we; /*Write enable of the memory transaction*/ \
    logic [2:0]                    size; /*Size of the memory transaction (log2 bytes)*/ \
    logic [Cfg.X_MEM_WIDTH/8-1:0]  be; /*Byte enables for memory transaction*/ \
    logic [1:0]                    attr; /*[0] modifiable, [1] unaligned*/ \
    logic [Cfg.X_MEM_WIDTH-1:0]    wdata; /*Write data of a store memory transaction*/ \
    logic                          last; /*Is this the last memory transaction of the instruction?*/ \
    logic                          spec; /*Is the memory transaction speculative?*/ \
}
`define X_MEM_RESP_T(Cfg) struct packed { \
    logic       exc; /*Did the memory request cause a synchronous exception?*/ \
    logic [5:0] exccode; /*Exception code*/ \
    logic       dbg; /*Did the memory request cause a debug trigger match?*/ \
}

// Memory result interface
`define X_MEM_RESULT_T(Cfg) struct packed { \
    logic [Cfg.X_HARTID_WIDTH-1:0] hartid; /*Identification of the hart offloading the instruction*/ \
    logic [Cfg.X_ID_WIDTH-1:0]     id; /*Identification of the offloaded instruction*/ \
    logic [Cfg.X_MEM_WIDTH-1:0]    rdata; /*Read data of a load memory transaction*/ \
    logic                          err; /*Did the instruction cause a bus error?*/ \
    logic                          dbg; /*Did the read data cause a debug trigger match?*/ \
}

`define X_REGISTER_T(Cfg, hartid_t, id_t, readregflags_t) struct packed { \
    hartid_t hartid;  /*Identification of the hart offloading the instruction*/ \
    id_t id;  /*Identification of the offloaded instruction*/ \
    logic [Cfg.X_NUM_RS-1:0][Cfg.X_RFR_WIDTH-1:0] rs;  /*Register file source operands for the offloaded instruction.*/ \
    readregflags_t rs_valid; /*Validity of the register file source operand(s).*/ \
}

`define X_COMMIT_T(Cfg, hartid_t, id_t) struct packed { \
    hartid_t hartid;  /*Identification of the hart offloading the instruction*/ \
    id_t id;  /*Identification of the offloaded instruction*/ \
    logic commit_kill;  /*Shall an offloaded instruction be killed?*/ \
}

`define X_RESULT_T(Cfg, hartid_t, id_t, writeregflags_t) struct packed { \
    hartid_t hartid;  /*Identification of the hart offloading the instruction*/ \
    id_t id;  /*Identification of the offloaded instruction*/ \
    logic [Cfg.X_RFW_WIDTH-1:0] data;  /*Register file write data value(s)*/ \
    logic [4:0] rd;  /*Register file destination address(es)*/ \
    writeregflags_t we;  /*Register file write enable(s)*/ \
    logic exc;  /*Did the instruction cause a synchronous exception? (memory interface)*/ \
    logic [5:0] exccode;  /*Exception code (memory interface)*/ \
    logic dbg;  /*Did the instruction cause a debug trigger match? (memory interface)*/ \
    logic err;  /*Did the instruction cause a bus error? (memory interface)*/ \
}

`define CVXIF_REQ_T(Cfg, x_compressed_req_t, x_issue_req_t, x_register_t, x_commit_t) struct packed { \
    logic              compressed_valid; \
    x_compressed_req_t compressed_req; \
    logic              issue_valid; \
    x_issue_req_t      issue_req; \
    logic              register_valid; \
    x_register_t       register; \
    logic              commit_valid; \
    x_commit_t         commit; \
    logic              mem_ready; \
    `X_MEM_RESP_T(Cfg) mem_resp; \
    logic              mem_result_valid; \
    `X_MEM_RESULT_T(Cfg) mem_result; \
    logic              result_ready; \
}

`define CVXIF_RESP_T(Cfg, x_compressed_resp_t, x_issue_resp_t, x_result_t) struct packed { \
    logic               compressed_ready; \
    x_compressed_resp_t compressed_resp; \
    logic               issue_ready; \
    x_issue_resp_t      issue_resp; \
    logic               register_ready; \
    logic               mem_valid; \
    `X_MEM_REQ_T(Cfg)   mem_req; \
    logic               result_valid; \
    x_result_t          result; \
}

`endif  // CVXIF_TYPES_SVH
