// Copyright 2018 ETH Zurich and University of Bologna.
// Copyright and related rights are licensed under the Solderpad Hardware
// License, Version 0.51 (the "License"); you may not use this file except in
// compliance with the License.  You may obtain a copy of the License at
// http://solderpad.org/licenses/SHL-0.51. Unless required by applicable law
// or agreed to in writing, software, hardware and materials distributed under
// this License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
// CONDITIONS OF ANY KIND, either express or implied. See the License for the
// specific language governing permissions and limitations under the License.
//
// Author: Florian Zaruba, ETH Zurich
// Date: 19.04.2017
// Description: Load Store Unit, handles address calculation and memory interface signals


module load_store_unit
  import ariane_pkg::*;
#(
    parameter config_pkg::cva6_cfg_t CVA6Cfg = config_pkg::cva6_cfg_empty,
    parameter type ypb_store_req_t = logic,
    parameter type ypb_store_rsp_t = logic,
    parameter type ypb_amo_req_t = logic,
    parameter type ypb_amo_rsp_t = logic,
    parameter type ypb_load_req_t = logic,
    parameter type ypb_load_rsp_t = logic,
    parameter type ypb_mmu_ptw_req_t = logic,
    parameter type ypb_mmu_ptw_rsp_t = logic,
    parameter type exception_t = logic,
    parameter type fu_data_t = logic,
    parameter type fetch_areq_t = logic,
    parameter type fetch_arsp_t = logic,
    parameter type lsu_ctrl_t = logic,
    parameter type x_mem_req_t = logic,
    parameter type x_mem_resp_t = logic,
    parameter type x_mem_result_t = logic
) (
    // Subsystem Clock - SUBSYSTEM
    input logic clk_i,
    // Asynchronous reset active low - SUBSYSTEM
    input logic rst_ni,
    // Flush - CONTROLLER
    input logic flush_i,
    // No store pending - COMMIT_STAGE
    output logic no_st_pending_o,
    // Shared TLB is busy processing a multi-cycle flush
    output logic shared_tlb_flush_busy_o,
    // TO_BE_COMPLETED - TO_BE_COMPLETED
    input logic amo_valid_commit_i,
    // TO_BE_COMPLETED - TO_BE_COMPLETED
    input logic [31:0] tinst_i,
    // FU data needed to execute instruction - ISSUE_STAGE
    input fu_data_t fu_data_i,
    // Load Store Unit is ready - ISSUE_STAGE
    output logic lsu_ready_o,
    // Load Store Unit instruction is valid - ISSUE_STAGE
    input logic lsu_valid_i,

    // Load transaction ID - ISSUE_STAGE
    output logic [CVA6Cfg.TRANS_ID_BITS-1:0] load_trans_id_o,
    // Load result - ISSUE_STAGE
    output logic [CVA6Cfg.XLEN-1:0] load_result_o,
    // Load result is valid - ISSUE_STAGE
    output logic load_valid_o,
    // Load exception - ISSUE_STAGE
    output exception_t load_exception_o,

    // Store transaction ID - ISSUE_STAGE
    output logic [CVA6Cfg.TRANS_ID_BITS-1:0] store_trans_id_o,
    // Store result - ISSUE_STAGE
    output logic [CVA6Cfg.XLEN-1:0] store_result_o,
    // Store result is valid - ISSUE_STAGE
    output logic store_valid_o,
    // Store exception - ISSUE_STAGE
    output exception_t store_exception_o,

    // Commit the first pending store - COMMIT_STAGE
    input logic commit_i,
    // Commit queue is ready to accept another commit request - COMMIT_STAGE
    output logic commit_ready_o,
    // Commit transaction ID - COMMIT_STAGE
    input logic [CVA6Cfg.TRANS_ID_BITS-1:0] commit_tran_id_i,
    // The committing instruction is dropped (speculative scoreboard) - COMMIT_STAGE
    input logic commit_drop_i,

    // Enable virtual memory translation - CSR_REGFILE
    input logic enable_translation_i,
    // Enable G-Stage memory translation - CSR_REGFILE
    input logic enable_g_translation_i,
    // Enable virtual memory translation for load/stores - CSR_REGFILE
    input logic en_ld_st_translation_i,
    // Enable G-Stage memory translation for load/stores - CSR_REGFILE
    input logic en_ld_st_g_translation_i,

    // Instruction cache input request - FETCH
    input  fetch_areq_t fetch_areq_i,
    // Instruction cache output response - FETCH
    output fetch_arsp_t fetch_arsp_o,

    // Current privilege mode - CSR_REGFILE
    input riscv::priv_lvl_t priv_lvl_i,
    // Data Endian mode - CSR_REGFILE
    input logic mbe_i,
    // Current virtualization mode - CSR_REGFILE
    input logic v_i,
    // Privilege level at which load and stores should happen - CSR_REGFILE
    input riscv::priv_lvl_t ld_st_priv_lvl_i,
    // Virtualization mode at which load and stores should happen - CSR_REGFILE
    input logic ld_st_v_i,
    // Instruction is a hyp load/store - CSR_REGFILE
    output logic csr_hs_ld_st_inst_o,
    // Supervisor User Memory - CSR_REGFILE
    input logic sum_i,
    // Virtual Supervisor User Memory - CSR_REGFILE
    input logic vs_sum_i,
    // Make Executable Readable - CSR_REGFILE
    input logic mxr_i,
    // Make Executable Readable Virtual Supervisor - CSR_REGFILE
    input logic vmxr_i,
    // TO_BE_COMPLETED - TO_BE_COMPLETED
    input logic [CVA6Cfg.PPNW-1:0] satp_ppn_i,
    // TO_BE_COMPLETED - TO_BE_COMPLETED
    input logic [CVA6Cfg.ASID_WIDTH-1:0] asid_i,
    // TO_BE_COMPLETED - TO_BE_COMPLETED
    input logic [CVA6Cfg.PPNW-1:0] vsatp_ppn_i,
    // TO_BE_COMPLETED - TO_BE_COMPLETED
    input logic [CVA6Cfg.ASID_WIDTH-1:0] vs_asid_i,
    // TO_BE_COMPLETED - TO_BE_COMPLETED
    input logic [CVA6Cfg.PPNW-1:0] hgatp_ppn_i,
    // TO_BE_COMPLETED - TO_BE_COMPLETED
    input logic [CVA6Cfg.VMID_WIDTH-1:0] vmid_i,
    // TO_BE_COMPLETED - TO_BE_COMPLETED
    input logic [CVA6Cfg.ASID_WIDTH-1:0] asid_to_be_flushed_i,
    // TO_BE_COMPLETED - TO_BE_COMPLETED
    input logic [CVA6Cfg.VMID_WIDTH-1:0] vmid_to_be_flushed_i,
    // TO_BE_COMPLETED - TO_BE_COMPLETED
    input logic [CVA6Cfg.VLEN-1:0] vaddr_to_be_flushed_i,
    // TO_BE_COMPLETED - TO_BE_COMPLETED
    input logic [CVA6Cfg.GPLEN-1:0] gpaddr_to_be_flushed_i,
    // TLB flush - CONTROLLER
    input logic flush_tlb_i,
    input logic flush_tlb_vvma_i,
    input logic flush_tlb_gvma_i,
    // Instruction TLB miss - PERF_COUNTERS
    output logic itlb_miss_o,
    // Data TLB miss - PERF_COUNTERS
    output logic dtlb_miss_o,
    // Store cache response - DCACHE
    output ypb_store_req_t ypb_store_req_o,
    // Store cache request - DCACHE
    input ypb_store_rsp_t ypb_store_rsp_i,
    // AMO request - DCACHE
    output ypb_amo_req_t ypb_amo_req_o,
    // AMO response - DCACHE
    input ypb_amo_rsp_t ypb_amo_rsp_i,
    // Load cache response - DCACHE
    output ypb_load_req_t ypb_load_req_o,
    // Load cache request - DCACHE
    input ypb_load_rsp_t ypb_load_rsp_i,
    // MMU PTW cache response - DCACHE
    output ypb_mmu_ptw_req_t ypb_mmu_ptw_req_o,
    // MMU PTW cache request - DCACHE
    input ypb_mmu_ptw_rsp_t ypb_mmu_ptw_rsp_i,
    // TO_BE_COMPLETED - TO_BE_COMPLETED
    input logic dcache_wbuffer_empty_i,
    // TO_BE_COMPLETED - TO_BE_COMPLETED
    input logic dcache_wbuffer_not_ni_i,
    // PMP configuration - CSR_REGFILE
    input riscv::pmpcfg_t [avoid_neg(CVA6Cfg.NrPMPEntries-1):0] pmpcfg_i,
    // PMP address - CSR_REGFILE
    input logic [avoid_neg(CVA6Cfg.NrPMPEntries-1):0][CVA6Cfg.PLEN-3:0] pmpaddr_i,

    // RVFI information - RVFI
    output lsu_ctrl_t                    rvfi_lsu_ctrl_o,
    // RVFI information - RVFI
    output logic      [CVA6Cfg.PLEN-1:0] rvfi_mem_paddr_o,
    //Trigger module communication
    input  logic                         sdtrig_load_cancel_i,
    input  logic      [CVA6Cfg.XLEN-1:0] sdtrig_load_action_i,
    output logic                         sdtrig_load_data_valid_o,
    output logic      [CVA6Cfg.XLEN-1:0] sdtrig_load_data_o,
    input  logic      [CVA6Cfg.XLEN-1:0] sdtrig_load_data_action_i,
    input  logic                         sdtrig_store_stall_i,
    input  logic      [CVA6Cfg.XLEN-1:0] sdtrig_store_action_i,

    // CV-X-IF memory (request/response) interface - SUBSYSTEM
    input  logic          x_mem_valid_i,
    output logic          x_mem_ready_o,
    input  x_mem_req_t    x_mem_req_i,
    output x_mem_resp_t   x_mem_resp_o,
    // CV-X-IF memory result interface - SUBSYSTEM
    output logic          x_mem_result_valid_o,
    output x_mem_result_t x_mem_result_o,
    // Exception of the last X-IF memory transaction, kept by the CVXIF FU
    // until the result of the instruction comes back - EX_STAGE
    output logic          x_mem_ex_valid_o,
    output exception_t    x_mem_ex_o,
    // An X-IF instruction has done its last memory transaction - ISSUE_STAGE
    output logic          x_mem_done_o
);

  // data is misaligned
  logic                             data_misaligned;

  // ------------------------------
  // Request source: issue or X-IF
  // ------------------------------
  // The LSU executes the requests of the issue stage and the memory requests
  // of a CV-X-IF coprocessor. Both go through the same path from here on.
  fu_data_t                         lsu_fu_data;
  logic                             lsu_valid;
  logic      [                31:0] lsu_tinst;
  // An X-IF memory request enters the LSU this cycle
  logic                             x_inject;
  fu_data_t                         x_fu_data;
  // Commit of the oldest speculative store: from the commit stage or for an
  // X-IF store
  logic                             x_st_commit;
  logic                             st_commit;
  // Outputs of the load/store pipeline registers, before the X-IF demux
  logic                             load_valid_q;
  logic                             store_valid_q;
  logic                             x_ld_match;
  logic                             x_st_match;

  assign lsu_fu_data = x_inject ? x_fu_data : fu_data_i;
  assign lsu_valid   = lsu_valid_i || x_inject;
  assign lsu_tinst   = x_inject ? '0 : tinst_i;
  assign st_commit   = commit_i || x_st_commit;
  // --------------------------------------
  // 1st register stage - (stall registers)
  // --------------------------------------
  // those are the signals which are always correct
  // e.g.: they keep the value in the stall case
  lsu_ctrl_t                        lsu_ctrl;

  logic                             pop_st;
  logic                             pop_ld;

  // ------------------------------
  // Address Generation Unit (AGU)
  // ------------------------------
  // virtual address as calculated by the AGU in the first cycle
  logic      [    CVA6Cfg.VLEN-1:0] vaddr_i;
  logic      [    CVA6Cfg.XLEN-1:0] vaddr_xlen;
  logic                             overflow;
  logic                             g_overflow;
  logic      [(CVA6Cfg.XLEN/8)-1:0] be_i;

  assign vaddr_xlen = $unsigned($signed(lsu_fu_data.imm) + $signed(lsu_fu_data.operand_a));
  assign vaddr_i = vaddr_xlen[CVA6Cfg.VLEN-1:0];
  // we work with SV39 or SV32, so if VM is enabled, check that all bits [XLEN-1:38] or [XLEN-1:31] are equal
  assign overflow = (CVA6Cfg.IS_XLEN64 && (!((&vaddr_xlen[CVA6Cfg.XLEN-1:CVA6Cfg.SV-1]) == 1'b1 || (|vaddr_xlen[CVA6Cfg.XLEN-1:CVA6Cfg.SV-1]) == 1'b0)));
  if (CVA6Cfg.RVH) begin : gen_g_overflow_hyp
    assign g_overflow = (CVA6Cfg.IS_XLEN64 && (!((|vaddr_xlen[CVA6Cfg.XLEN-1:CVA6Cfg.SVX]) == 1'b0)));
  end else begin : gen_g_overflow_no_hyp
    assign g_overflow = 1'b0;
  end

  logic                    st_valid_i;
  logic                    ld_valid_i;
  logic                    ld_translation_req;
  logic                    st_translation_req;
  logic [CVA6Cfg.VLEN-1:0] ld_vaddr;
  logic [            31:0] ld_tinst;
  logic                    ld_hs_ld_st_inst;
  logic                    ld_hlvx_inst;
  logic [CVA6Cfg.VLEN-1:0] st_vaddr;
  logic [            31:0] st_tinst;
  logic                    st_hs_ld_st_inst;
  logic                    st_hlvx_inst;
  logic                    translation_req;
  logic                    translation_valid;
  logic [CVA6Cfg.VLEN-1:0] mmu_vaddr;
  logic [CVA6Cfg.PLEN-1:0] mmu_paddr, fetch_vaddr_plen, lsu_paddr;
  logic        [         CVA6Cfg.VLEN-1:0] pmp_vaddr_q;
  logic                                    pmp_is_store_q;
  logic                                    pmp_hlvx_inst_q;
  logic        [                     31:0] mmu_tinst;
  logic                                    mmu_hs_ld_st_inst;
  logic                                    mmu_hlvx_inst;
  exception_t                              mmu_exception;
  exception_t                              pmp_exception;
  fetch_arsp_t                             pmp_fetch_arsp;
  logic                                    pmp_translation_valid;
  logic                                    dtlb_hit;
  logic        [         CVA6Cfg.PPNW-1:0] dtlb_ppn;

  logic                                    ld_valid;
  logic        [CVA6Cfg.TRANS_ID_BITS-1:0] ld_trans_id;
  logic        [         CVA6Cfg.XLEN-1:0] ld_result;
  logic                                    st_valid;
  logic        [CVA6Cfg.TRANS_ID_BITS-1:0] st_trans_id;
  logic        [         CVA6Cfg.XLEN-1:0] st_result;

  logic        [                     11:0] page_offset;
  logic                                    page_offset_matches;

  exception_t                              misaligned_exception;
  exception_t                              ld_ex;
  exception_t                              st_ex;

  logic                                    hs_ld_st_inst;
  logic                                    hlvx_inst;

  logic [1:0] sum, mxr;
  logic [CVA6Cfg.PPNW-1:0] satp_ppn[2:0];
  logic [CVA6Cfg.ASID_WIDTH-1:0] asid[2:0], asid_to_be_flushed[1:0];
  logic [CVA6Cfg.VLEN-1:0] vaddr_to_be_flushed[1:0];
  // -------------------
  // MMU e.g.: TLBs/PTW
  // -------------------

  if (CVA6Cfg.MmuPresent) begin : gen_mmu
    localparam HYP_EXT = CVA6Cfg.RVH ? 1 : 0;

    cva6_mmu #(
        .CVA6Cfg          (CVA6Cfg),
        .exception_t      (exception_t),
        .fetch_areq_t     (fetch_areq_t),
        .fetch_arsp_t     (fetch_arsp_t),
        .ypb_mmu_ptw_req_t(ypb_mmu_ptw_req_t),
        .ypb_mmu_ptw_rsp_t(ypb_mmu_ptw_rsp_t),
        .HYP_EXT          (HYP_EXT)
    ) i_cva6_mmu (
        .clk_i(clk_i),
        .rst_ni(rst_ni),
        .flush_i(flush_i),
        .enable_translation_i(enable_translation_i),
        .enable_g_translation_i(enable_g_translation_i),
        .en_ld_st_translation_i(en_ld_st_translation_i),
        .en_ld_st_g_translation_i(en_ld_st_g_translation_i),
        .fetch_areq_i(fetch_areq_i),
        .fetch_arsp_o(pmp_fetch_arsp),
        // misaligned bypass
        .misaligned_ex_i(misaligned_exception),
        .lsu_req_i(translation_req),
        .lsu_vaddr_i(mmu_vaddr),
        .lsu_tinst_i(mmu_tinst),
        .lsu_is_store_i(st_translation_req),
        .csr_hs_ld_st_inst_o(csr_hs_ld_st_inst_o),
        .lsu_dtlb_hit_o(dtlb_hit),  // send in the same cycle as the request
        .lsu_dtlb_ppn_o(dtlb_ppn),  // send in the same cycle as the request

        .lsu_valid_o    (pmp_translation_valid),
        .lsu_paddr_o    (lsu_paddr),
        .lsu_exception_o(pmp_exception),
        .lsu_vaddr_o    (pmp_vaddr_q),
        .lsu_is_store_o (pmp_is_store_q),
        .lsu_hlvx_inst_o(pmp_hlvx_inst_q),

        .priv_lvl_i      (priv_lvl_i),
        .v_i,
        .ld_st_priv_lvl_i(ld_st_priv_lvl_i),
        .ld_st_v_i,
        .sum_i,
        .vs_sum_i,
        .mxr_i,
        .vmxr_i,
        .mbe_i           (mbe_i),

        .hlvx_inst_i    (mmu_hlvx_inst),
        .hs_ld_st_inst_i(mmu_hs_ld_st_inst),
        .satp_ppn_i,
        .vsatp_ppn_i,
        .hgatp_ppn_i,
        .asid_i,
        .vs_asid_i,
        .asid_to_be_flushed_i,
        .vmid_i,
        .vmid_to_be_flushed_i,
        .vaddr_to_be_flushed_i,
        .gpaddr_to_be_flushed_i,
        .flush_tlb_i,
        .flush_tlb_vvma_i,
        .flush_tlb_gvma_i,

        .itlb_miss_o(itlb_miss_o),
        .dtlb_miss_o(dtlb_miss_o),
        .shared_tlb_flush_busy_o(shared_tlb_flush_busy_o),

        .ypb_mmu_ptw_req_o(ypb_mmu_ptw_req_o),
        .ypb_mmu_ptw_rsp_i(ypb_mmu_ptw_rsp_i),

        .pmpcfg_i,
        .pmpaddr_i
    );
  end else begin : gen_no_mmu
    // fetch request without MMU, virtual and physical address are identical
    assign pmp_fetch_arsp.fetch_valid = fetch_areq_i.fetch_req;
    assign shared_tlb_flush_busy_o = 1'b0;  //default 0 for shared_tlb flush
    if (CVA6Cfg.VLEN >= CVA6Cfg.PLEN) begin : gen_virtual_physical_address_instruction_vlen_greater
      assign pmp_fetch_arsp.fetch_paddr = fetch_areq_i.fetch_vaddr[CVA6Cfg.PLEN-1:0];
    end else begin : gen_virtual_physical_address_instruction_plen_greater
      assign pmp_fetch_arsp.fetch_paddr = CVA6Cfg.PLEN'(fetch_areq_i.fetch_vaddr);
    end
    assign pmp_fetch_arsp.fetch_exception = 'h0;

    assign itlb_miss_o = 1'b0;
    assign dtlb_miss_o = 1'b0;
    assign dtlb_hit = 1'b1;

    //  The PMP checks the request in the cycle it is presented.
    assign pmp_translation_valid = translation_req;
    assign pmp_exception = misaligned_exception;
    assign pmp_vaddr_q = mmu_vaddr;
    assign pmp_is_store_q = st_translation_req;
    assign pmp_hlvx_inst_q = mmu_hlvx_inst;
    if (CVA6Cfg.VLEN > CVA6Cfg.PLEN) begin : gen_paddr_vlen_greater
      assign lsu_paddr = mmu_vaddr[CVA6Cfg.PLEN-1:0];
    end else begin : gen_paddr_plen_greater
      assign lsu_paddr = CVA6Cfg.PLEN'(mmu_vaddr);
    end
    assign dtlb_ppn = lsu_paddr[CVA6Cfg.PLEN-1:12];

  end

  // ------------------
  // PMP
  // ------------------

  pmp_data_if #(
      .CVA6Cfg      (CVA6Cfg),
      .icache_areq_t(fetch_arsp_t),
      .exception_t  (exception_t)
  ) i_pmp_data_if (
      .clk_i               (clk_i),
      .rst_ni              (rst_ni),
      .icache_areq_i       (pmp_fetch_arsp),
      .icache_areq_o       (fetch_arsp_o),
      .icache_fetch_vaddr_i(fetch_areq_i.fetch_vaddr),
      .lsu_valid_i         (pmp_translation_valid),
      .lsu_paddr_i         (lsu_paddr),
      .lsu_vaddr_i         (pmp_vaddr_q),
      .lsu_exception_i     (pmp_exception),
      .lsu_is_store_i      (pmp_is_store_q),
      .lsu_hlvx_inst_i     (pmp_hlvx_inst_q),
      .lsu_valid_o         (translation_valid),
      .lsu_paddr_o         (mmu_paddr),
      .lsu_exception_o     (mmu_exception),
      .priv_lvl_i          (priv_lvl_i),
      .v_i                 (v_i),
      .ld_st_priv_lvl_i    (ld_st_priv_lvl_i),
      .ld_st_v_i           (ld_st_v_i),
      .pmpcfg_i            (pmpcfg_i),
      .pmpaddr_i           (pmpaddr_i)
  );


  // The load unit reads the translated address and its exception in s1 with
  // TwoPhaseReq. With an MMU the MMU provides them there. Without one the
  // translation and the PMP check happen in the request cycle, as for a store,
  // and their result is registered for the load.
  logic [CVA6Cfg.PLEN-1:0] ld_paddr;
  exception_t ld_ex_s1;
  if (CVA6Cfg.TwoPhaseReq && !CVA6Cfg.MmuPresent) begin : gen_ld_s1
    logic [CVA6Cfg.PLEN-1:0] ld_paddr_q;
    exception_t ld_ex_q;
    always_ff @(posedge clk_i or negedge rst_ni) begin
      if (~rst_ni) begin
        ld_paddr_q <= '0;
        ld_ex_q    <= '0;
      end else begin
        ld_paddr_q <= mmu_paddr;
        ld_ex_q    <= mmu_exception;
        ld_ex_q.valid <= mmu_exception.valid && ld_translation_req && ld_valid_i;
      end
    end
    assign ld_paddr = ld_paddr_q;
    assign ld_ex_s1 = ld_ex_q;
  end else begin : gen_ld_direct
    assign ld_paddr = mmu_paddr;
    assign ld_ex_s1 = mmu_exception;
  end

  logic store_buffer_empty;
  // ------------------
  // Store Unit
  // ------------------
  store_unit #(
      .CVA6Cfg(CVA6Cfg),
      .ypb_store_req_t(ypb_store_req_t),
      .ypb_store_rsp_t(ypb_store_rsp_t),
      .ypb_amo_req_t(ypb_amo_req_t),
      .ypb_amo_rsp_t(ypb_amo_rsp_t),
      .exception_t(exception_t),
      .lsu_ctrl_t(lsu_ctrl_t)
  ) i_store_unit (
      .clk_i,
      .rst_ni,
      .flush_i,
      .no_st_pending_o,
      .store_buffer_empty_o(store_buffer_empty),

      .valid_i   (st_valid_i),
      .lsu_ctrl_i(lsu_ctrl),
      .pop_st_o  (pop_st),
      .commit_i  (st_commit),
      .commit_ready_o,
      .amo_valid_commit_i,
      .mbe_i     (mbe_i),

      .valid_o              (st_valid),
      .trans_id_o           (st_trans_id),
      .result_o             (st_result),
      .ex_o                 (st_ex),
      // MMU port
      .translation_req_o    (st_translation_req),
      .vaddr_o              (st_vaddr),
      .tinst_o              (st_tinst),
      .hs_ld_st_inst_o      (st_hs_ld_st_inst),
      .hlvx_inst_o          (st_hlvx_inst),
      .paddr_i              (mmu_paddr),
      .ex_i                 (mmu_exception),
      .dtlb_hit_i           (dtlb_hit),
      // Load Unit
      .page_offset_i        (page_offset),
      .page_offset_matches_o(page_offset_matches),
      // to memory arbiter
      .ypb_amo_req_o        (ypb_amo_req_o),
      .ypb_amo_rsp_i        (ypb_amo_rsp_i),
      .ypb_store_req_o      (ypb_store_req_o),
      .ypb_store_rsp_i      (ypb_store_rsp_i),
      //Trigger module
      .sdtrig_store_stall_i (sdtrig_store_stall_i),
      .sdtrig_store_action_i(sdtrig_store_action_i)
  );

  // ------------------
  // Load Unit
  // ------------------
  load_unit #(
      .CVA6Cfg       (CVA6Cfg),
      .ypb_load_req_t(ypb_load_req_t),
      .ypb_load_rsp_t(ypb_load_rsp_t),
      .exception_t   (exception_t),
      .lsu_ctrl_t    (lsu_ctrl_t)
  ) i_load_unit (
      .clk_i,
      .rst_ni,
      .flush_i,
      .valid_i   (ld_valid_i),
      .lsu_ctrl_i(lsu_ctrl),
      .pop_ld_o  (pop_ld),

      .valid_o              (ld_valid),
      .trans_id_o           (ld_trans_id),
      .result_o             (ld_result),
      .ex_o                 (ld_ex),
      .mbe_i                (mbe_i),
      // MMU port
      .translation_req_o    (ld_translation_req),
      .vaddr_o              (ld_vaddr),
      .tinst_o              (ld_tinst),
      .hs_ld_st_inst_o      (ld_hs_ld_st_inst),
      .hlvx_inst_o          (ld_hlvx_inst),
      .paddr_i              (ld_paddr),
      .ex_i                 (ld_ex_s1),
      .dtlb_hit_i           (dtlb_hit),
      .dtlb_ppn_i           (dtlb_ppn),
      // to store unit
      .page_offset_o        (page_offset),
      .page_offset_matches_i(page_offset_matches),
      .store_buffer_empty_i (store_buffer_empty),
      .commit_tran_id_i,
      .commit_drop_i,
      // to memory arbiter
      .ypb_load_req_o       (ypb_load_req_o),
      .ypb_load_rsp_i       (ypb_load_rsp_i),
      .dcache_wbuffer_not_ni_i,
      //sdtrig
      .sdtrig_load_cancel_i (sdtrig_load_cancel_i),
      .sdtrig_load_action_i (sdtrig_load_action_i)
  );

  // ----------------------------
  // Output Pipeline Register
  // ----------------------------

  // amount of pipeline registers inserted for load/store return path
  // can be tuned to trade-off IPC vs. cycle time

  exception_t load_exception;

  shift_reg #(
      .dtype(logic [$bits(ld_valid) + $bits(ld_trans_id) + $bits(ld_result) + $bits(ld_ex) - 1:0]),
      .Depth(CVA6Cfg.NrLoadPipeRegs)
  ) i_pipe_reg_load (
      .clk_i,
      .rst_ni,
      .d_i({ld_valid, ld_trans_id, ld_result, ld_ex}),
      .d_o({load_valid_q, load_trans_id_o, load_result_o, load_exception})
  );
  // The result of an X-IF load goes back to the coprocessor, not to the
  // scoreboard.
  assign load_valid_o = load_valid_q && !x_ld_match;

  // Load data trigger: the result is compared as it leaves the output
  // register, with the load it belongs to, so the break and the load retire
  // together whatever NrLoadPipeRegs. It breaks after the load: the load
  // writes its result and the commit stage raises the break on the next
  // instruction (exception timing). A load that raised an exception has no
  // data to compare.
  assign sdtrig_load_data_valid_o = CVA6Cfg.SdtrigMcontrol6LoadData && load_valid_o && !load_exception.valid;
  assign sdtrig_load_data_o = load_result_o;
  always_comb begin
    load_exception_o = load_exception;
    if (sdtrig_load_data_valid_o && sdtrig_load_data_action_i != '0) begin
      load_exception_o.cause  = sdtrig_load_data_action_i;
      load_exception_o.timing = 1'b1;
    end
  end

  shift_reg #(
      .dtype(logic [$bits(st_valid) + $bits(st_trans_id) + $bits(st_result) + $bits(st_ex) - 1:0]),
      .Depth(CVA6Cfg.NrStorePipeRegs)
  ) i_pipe_reg_store (
      .clk_i,
      .rst_ni,
      .d_i({st_valid, st_trans_id, st_result, st_ex}),
      .d_o({store_valid_q, store_trans_id_o, store_result_o, store_exception_o})
  );
  assign store_valid_o = store_valid_q && !x_st_match;

  // determine whether this is a load or store
  always_comb begin : which_op

    ld_valid_i        = 1'b0;
    st_valid_i        = 1'b0;

    translation_req   = 1'b0;
    mmu_vaddr         = {CVA6Cfg.VLEN{1'b0}};
    mmu_tinst         = {32{1'b0}};
    mmu_hs_ld_st_inst = 1'b0;
    mmu_hlvx_inst     = 1'b0;

    // check the operation to activate the right functional unit accordingly
    unique case (lsu_ctrl.fu)
      // all loads go here
      LOAD: begin
        ld_valid_i      = lsu_ctrl.valid;
        translation_req = ld_translation_req;
        mmu_vaddr       = ld_vaddr;
        if (CVA6Cfg.RVH) begin
          mmu_tinst         = ld_tinst;
          mmu_hs_ld_st_inst = ld_hs_ld_st_inst;
          mmu_hlvx_inst     = ld_hlvx_inst;
        end
      end
      // all stores go here
      STORE: begin
        st_valid_i      = lsu_ctrl.valid;
        translation_req = st_translation_req;
        mmu_vaddr       = st_vaddr;
        if (CVA6Cfg.RVH) begin
          mmu_tinst         = st_tinst;
          mmu_hs_ld_st_inst = st_hs_ld_st_inst;
          mmu_hlvx_inst     = st_hlvx_inst;
        end
      end
      // not relevant for the LSU
      default: ;
    endcase
  end

  // ------------------------
  // Hypervisor Load/Store
  // ------------------------
  // determine whether this is a hypervisor load or store
  if (CVA6Cfg.RVH) begin
    always_comb begin : hyp_ld_st
      // check the operator to activate the right functional unit accordingly
      hs_ld_st_inst = 1'b0;
      hlvx_inst     = 1'b0;
      case (lsu_ctrl.operation)
        // all loads go here
        HLV_B, HLV_BU, HLV_H, HLV_HU, HLV_W, HSV_B, HSV_H, HSV_W, HLV_WU, HLV_D, HSV_D: begin
          hs_ld_st_inst = 1'b1;
        end
        HLVX_WU, HLVX_HU: begin
          hs_ld_st_inst = 1'b1;
          hlvx_inst     = 1'b1;
        end
        default: ;
      endcase
    end
  end else begin
    assign hs_ld_st_inst = 1'b0;
    assign hlvx_inst     = 1'b0;
  end

  // ---------------
  // Byte Enable
  // ---------------
  // we can generate the byte enable from the virtual address since the last
  // 12 bit are the same anyway
  // and we can always generate the byte enable from the address at hand

  if (CVA6Cfg.IS_XLEN64) begin : gen_8b_be
    assign be_i = be_gen(vaddr_i[2:0], extract_transfer_size(lsu_fu_data.operation));
  end else begin : gen_4b_be
    assign be_i = be_gen_32(vaddr_i[1:0], extract_transfer_size(lsu_fu_data.operation));
  end

  // ------------------------
  // Misaligned Exception
  // ------------------------
  // we can detect a misaligned exception immediately
  // the misaligned exception is passed to the functional unit via the MMU, which in case
  // can augment the exception if other memory related exceptions like a page fault or access errors
  always_comb begin : data_misaligned_detection
    misaligned_exception = '0;
    data_misaligned = 1'b0;

    if (lsu_ctrl.valid) begin
      if (CVA6Cfg.IS_XLEN64) begin
        case (lsu_ctrl.operation)
          // double word
          LD, SD, FLD, FSD,
                  AMO_LRD, AMO_SCD,
                  AMO_SWAPD, AMO_ADDD, AMO_ANDD, AMO_ORD,
                  AMO_XORD, AMO_MAXD, AMO_MAXDU, AMO_MIND,
                  AMO_MINDU, HLV_D, HSV_D: begin
            if (lsu_ctrl.vaddr[2:0] != 3'b000) begin
              data_misaligned = 1'b1;
            end
          end
          default: ;
        endcase
      end
      case (lsu_ctrl.operation)
        // word
        LW, LWU, SW, FLW, FSW,
                AMO_LRW, AMO_SCW,
                AMO_SWAPW, AMO_ADDW, AMO_ANDW, AMO_ORW,
                AMO_XORW, AMO_MAXW, AMO_MAXWU, AMO_MINW,
                AMO_MINWU, HLV_W, HLV_WU, HLVX_WU, HSV_W: begin
          if (lsu_ctrl.vaddr[1:0] != 2'b00) begin
            data_misaligned = 1'b1;
          end
        end
        // half word
        LH, LHU, SH, FLH, FSH, HLV_H, HLV_HU, HLVX_HU, HSV_H: begin
          if (lsu_ctrl.vaddr[0] != 1'b0) begin
            data_misaligned = 1'b1;
          end
        end
        // byte -> is always aligned
        default: ;
      endcase
    end

    if (data_misaligned) begin
      case (lsu_ctrl.fu)
        LOAD: begin
          misaligned_exception.cause = riscv::LD_ADDR_MISALIGNED;
          misaligned_exception.valid = 1'b1;
          if (CVA6Cfg.TvalEn)
            misaligned_exception.tval = {{CVA6Cfg.XLEN - CVA6Cfg.VLEN{1'b0}}, lsu_ctrl.vaddr};
          if (CVA6Cfg.RVH) begin
            misaligned_exception.tval2 = '0;
            misaligned_exception.tinst = lsu_ctrl.tinst;
            misaligned_exception.gva   = ld_st_v_i;
          end
        end
        STORE: begin

          misaligned_exception.cause = riscv::ST_ADDR_MISALIGNED;
          misaligned_exception.valid = 1'b1;
          if (CVA6Cfg.TvalEn)
            misaligned_exception.tval = {{CVA6Cfg.XLEN - CVA6Cfg.VLEN{1'b0}}, lsu_ctrl.vaddr};
          if (CVA6Cfg.RVH) begin
            misaligned_exception.tval2 = '0;
            misaligned_exception.tinst = lsu_ctrl.tinst;
            misaligned_exception.gva   = ld_st_v_i;
          end
        end
        default: ;
      endcase
    end

    if (CVA6Cfg.MmuPresent && en_ld_st_translation_i && lsu_ctrl.overflow) begin

      case (lsu_ctrl.fu)
        LOAD: begin
          misaligned_exception.cause = riscv::LOAD_PAGE_FAULT;
          misaligned_exception.valid = 1'b1;
          if (CVA6Cfg.TvalEn)
            misaligned_exception.tval = {{CVA6Cfg.XLEN - CVA6Cfg.VLEN{1'b0}}, lsu_ctrl.vaddr};
          if (CVA6Cfg.RVH) begin
            misaligned_exception.tval2 = '0;
            misaligned_exception.tinst = lsu_ctrl.tinst;
            misaligned_exception.gva   = ld_st_v_i;
          end
        end
        STORE: begin
          misaligned_exception.cause = riscv::STORE_PAGE_FAULT;
          misaligned_exception.valid = 1'b1;
          if (CVA6Cfg.TvalEn)
            misaligned_exception.tval = {{CVA6Cfg.XLEN - CVA6Cfg.VLEN{1'b0}}, lsu_ctrl.vaddr};
          if (CVA6Cfg.RVH) begin
            misaligned_exception.tval2 = '0;
            misaligned_exception.tinst = lsu_ctrl.tinst;
            misaligned_exception.gva   = ld_st_v_i;
          end
        end
        default: ;
      endcase
    end

    if (CVA6Cfg.MmuPresent && CVA6Cfg.RVH && en_ld_st_g_translation_i && !en_ld_st_translation_i && lsu_ctrl.g_overflow) begin

      case (lsu_ctrl.fu)
        LOAD: begin
          misaligned_exception.cause = riscv::LOAD_GUEST_PAGE_FAULT;
          misaligned_exception.valid = 1'b1;
          if (CVA6Cfg.TvalEn)
            misaligned_exception.tval = {{CVA6Cfg.XLEN - CVA6Cfg.VLEN{1'b0}}, lsu_ctrl.vaddr};
          if (CVA6Cfg.RVH) begin
            misaligned_exception.tval2 = '0;
            misaligned_exception.tinst = lsu_ctrl.tinst;
            misaligned_exception.gva   = ld_st_v_i;
          end
        end
        STORE: begin
          misaligned_exception.cause = riscv::STORE_GUEST_PAGE_FAULT;
          misaligned_exception.valid = 1'b1;
          if (CVA6Cfg.TvalEn)
            misaligned_exception.tval = {{CVA6Cfg.XLEN - CVA6Cfg.VLEN{1'b0}}, lsu_ctrl.vaddr};
          if (CVA6Cfg.RVH) begin
            misaligned_exception.tval2 = '0;
            misaligned_exception.tinst = lsu_ctrl.tinst;
            misaligned_exception.gva   = ld_st_v_i;
          end
        end
        default: ;
      endcase
    end
  end


  // ------------------
  // LSU Control
  // ------------------
  // new data arrives here
  lsu_ctrl_t lsu_req_i;

  assign lsu_req_i = {
    lsu_valid,
    vaddr_i,
    lsu_tinst,
    hs_ld_st_inst,
    hlvx_inst,
    overflow,
    g_overflow,
    lsu_fu_data.operand_b,
    be_i,
    lsu_fu_data.fu,
    lsu_fu_data.operation,
    lsu_fu_data.trans_id
  };

  lsu_bypass #(
      .CVA6Cfg(CVA6Cfg),
      .lsu_ctrl_t(lsu_ctrl_t)
  ) lsu_bypass_i (
      .clk_i,
      .rst_ni,
      .flush_i,
      .lsu_req_i      (lsu_req_i),
      .lsu_req_valid_i(lsu_valid),
      .pop_ld_i       (pop_ld),
      .pop_st_i       (pop_st),

      .lsu_ctrl_o(lsu_ctrl),
      .ready_o   (lsu_ready_o)
  );

  // ------------------------------
  // CV-X-IF memory interface
  // ------------------------------
  // A memory request of the coprocessor is turned into a scalar load or store
  // and goes through the LSU like one (translation, PMP, store buffer, load
  // forwarding checks), tagged with the trans_id of its offloaded
  // instruction: the X-IF id is the scoreboard trans_id. Its result is taken
  // off the LSU output and returned on the X-IF instead of the scoreboard.
  //
  // Ordering, which makes this simple:
  // - A request is served only when its instruction is the oldest in the
  //   scoreboard, so it is not speculative and every older store is already
  //   committed.
  // - The issue stage issues no younger load or store while an instruction
  //   accepted with loadstore = 1 has memory transactions to do.
  // So the X-IF store is the only speculative store in the store buffer and
  // the LSU commits it itself: the commit stage cannot, the instruction does
  // not commit before its result, which comes after its stores.
  //
  // One transaction at a time: mem_ready is given only once the LSU is done
  // with the request, so mem_resp can carry its exception.
  //
  // Not handled in this sketch:
  // - be: the byte enables come from size and addr, a sparse be is not
  //   supported.
  // - mode: loads and stores use the effective privilege of the CSRs
  //   (ld_st_priv_lvl_i), as scalar ones do.
  // - dbg and err: no trigger match or bus error is reported.
  // - Big endian (mbe_i).
  localparam int unsigned XOffBits = $clog2(CVA6Cfg.XLEN / 8);

  typedef enum logic [1:0] {
    XIdle,      // waiting for a request of the oldest instruction
    XWaitLsu,   // the request is in the LSU
    XCommitSt,  // the store is in the store buffer, commit it
    XResp       // mem_ready, mem_resp
  } x_state_e;

  x_state_e x_state_d, x_state_q;
  logic [CVA6Cfg.X_HARTID_WIDTH-1:0] x_hartid_d, x_hartid_q;
  logic [CVA6Cfg.TRANS_ID_BITS-1:0] x_id_d, x_id_q;
  logic [XOffBits-1:0] x_off_d, x_off_q;
  logic x_we_d, x_we_q;
  logic x_last_d, x_last_q;
  exception_t x_ex_d, x_ex_q;
  logic [CVA6Cfg.XLEN-1:0] x_rdata_d, x_rdata_q;
  logic x_result_valid_d, x_result_valid_q;
  logic x_size_ok, x_at_head;

  if (CVA6Cfg.CvxifEn) begin : gen_x_mem
    // The request as a scalar load or store. The LSU wants the store data in
    // the low bits, the X-IF has it on its byte lanes.
    always_comb begin : x_mem_request
      x_fu_data           = '0;
      x_fu_data.fu        = x_mem_req_i.we ? STORE : LOAD;
      x_fu_data.operand_a = x_mem_req_i.addr;
      x_fu_data.operand_b = x_mem_req_i.wdata >> {x_mem_req_i.addr[XOffBits-1:0], 3'b000};
      x_fu_data.imm       = '0;
      x_fu_data.trans_id  = x_mem_req_i.id;
      // Zero extending loads: the coprocessor gets the raw bytes.
      unique case (x_mem_req_i.size)
        3'd0: x_fu_data.operation = x_mem_req_i.we ? SB : LBU;
        3'd1: x_fu_data.operation = x_mem_req_i.we ? SH : LHU;
        3'd2: x_fu_data.operation = x_mem_req_i.we ? SW : (CVA6Cfg.IS_XLEN64 ? LWU : LW);
        default: x_fu_data.operation = x_mem_req_i.we ? SD : LD;
      endcase
    end

    // The LSU moves at most XLEN bits per access.
    assign x_size_ok = x_mem_req_i.size <= 3'(XOffBits);
    // The commit pointer is the trans_id of the oldest instruction.
    assign x_at_head = x_mem_req_i.id == commit_tran_id_i && !commit_drop_i;

    assign x_ld_match = x_state_q == XWaitLsu && !x_we_q && load_valid_q && load_trans_id_o == x_id_q;
    assign x_st_match = x_state_q == XWaitLsu && x_we_q && store_valid_q && store_trans_id_o == x_id_q;

    always_comb begin : x_mem_fsm
      x_state_d        = x_state_q;
      x_hartid_d       = x_hartid_q;
      x_id_d           = x_id_q;
      x_off_d          = x_off_q;
      x_we_d           = x_we_q;
      x_last_d         = x_last_q;
      x_ex_d           = x_ex_q;
      x_rdata_d        = x_rdata_q;
      x_inject         = 1'b0;
      x_st_commit      = 1'b0;
      x_mem_ready_o    = 1'b0;
      x_mem_ex_valid_o = 1'b0;
      x_mem_done_o     = 1'b0;
      x_result_valid_d = 1'b0;

      unique case (x_state_q)
        XIdle: begin
          if (x_mem_valid_i && x_at_head) begin
            x_hartid_d = x_mem_req_i.hartid;
            x_id_d     = x_mem_req_i.id;
            x_off_d    = x_mem_req_i.addr[XOffBits-1:0];
            x_we_d     = x_mem_req_i.we;
            x_last_d   = x_mem_req_i.last;
            x_ex_d     = '0;
            x_rdata_d  = '0;
            if (!x_size_ok) begin
              // Wider than the LSU: answered with an access fault.
              x_ex_d.valid = 1'b1;
              x_ex_d.cause = x_mem_req_i.we ? riscv::ST_ACCESS_FAULT : riscv::LD_ACCESS_FAULT;
              x_ex_d.tval  = CVA6Cfg.TvalEn ? x_mem_req_i.addr : '0;
              x_state_d    = XResp;
            end else if (lsu_ready_o && !lsu_valid_i) begin
              // The issue stage has priority on the LSU input.
              x_inject  = 1'b1;
              x_state_d = XWaitLsu;
            end
          end
        end
        XWaitLsu: begin
          if (x_ld_match) begin
            x_ex_d    = load_exception;
            x_rdata_d = load_result_o << {x_off_q, 3'b000};
            x_state_d = XResp;
          end else if (x_st_match) begin
            x_ex_d    = store_exception_o;
            x_state_d = store_exception_o.valid ? XResp : XCommitSt;
          end
        end
        XCommitSt: begin
          // The store went into the store buffer at least a cycle ago.
          if (commit_ready_o) begin
            x_st_commit = 1'b1;
            x_state_d   = XResp;
          end
        end
        XResp: begin
          x_mem_ready_o    = 1'b1;
          // No memory result after a synchronous exception.
          x_result_valid_d = !x_ex_q.valid;
          x_mem_ex_valid_o = x_ex_q.valid;
          // After an exception the coprocessor sends no more requests for
          // the instruction.
          x_mem_done_o     = x_last_q || x_ex_q.valid;
          x_state_d        = XIdle;
        end
        default: x_state_d = XIdle;
      endcase

      if (flush_i) begin
        x_state_d = XIdle;
      end
    end

    always_ff @(posedge clk_i or negedge rst_ni) begin : x_mem_regs
      if (!rst_ni) begin
        x_state_q        <= XIdle;
        x_hartid_q       <= '0;
        x_id_q           <= '0;
        x_off_q          <= '0;
        x_we_q           <= 1'b0;
        x_last_q         <= 1'b0;
        x_ex_q           <= '0;
        x_rdata_q        <= '0;
        x_result_valid_q <= 1'b0;
      end else begin
        x_state_q        <= x_state_d;
        x_hartid_q       <= x_hartid_d;
        x_id_q           <= x_id_d;
        x_off_q          <= x_off_d;
        x_we_q           <= x_we_d;
        x_last_q         <= x_last_d;
        x_ex_q           <= x_ex_d;
        x_rdata_q        <= x_rdata_d;
        x_result_valid_q <= x_result_valid_d;
      end
    end

    assign x_mem_resp_o.exc       = x_ex_q.valid;
    assign x_mem_resp_o.exccode   = x_ex_q.cause[5:0];
    assign x_mem_resp_o.dbg       = 1'b0;
    assign x_mem_ex_o             = x_ex_q;

    // The memory result follows mem_ready by a cycle. x_*_q still hold the
    // transaction then: a new request is latched at the earliest in that cycle.
    assign x_mem_result_valid_o   = x_result_valid_q;
    assign x_mem_result_o.hartid  = x_hartid_q;
    assign x_mem_result_o.id      = x_id_q;
    assign x_mem_result_o.rdata   = x_rdata_q;
    assign x_mem_result_o.err     = 1'b0;
    assign x_mem_result_o.dbg     = 1'b0;

    //pragma translate_off
    x_mem_valid_held :
    assert property (@(posedge clk_i) disable iff (~rst_ni || flush_i)
        x_state_q != XIdle |-> x_mem_valid_i)
    else $error("[load_store_unit] X-IF mem_valid dropped before mem_ready");
    x_st_commit_alone :
    assert property (@(posedge clk_i) disable iff (~rst_ni) !(x_st_commit && commit_i))
    else $error("[load_store_unit] the commit stage committed a store under an X-IF store");
    //pragma translate_on
  end else begin : gen_no_x_mem
    assign x_fu_data            = '0;
    assign x_inject             = 1'b0;
    assign x_st_commit          = 1'b0;
    assign x_ld_match           = 1'b0;
    assign x_st_match           = 1'b0;
    assign x_mem_ready_o        = 1'b0;
    assign x_mem_resp_o         = '0;
    assign x_mem_result_valid_o = 1'b0;
    assign x_mem_result_o       = '0;
    assign x_mem_ex_valid_o     = 1'b0;
    assign x_mem_ex_o           = '0;
    assign x_mem_done_o         = 1'b0;
  end

  assign rvfi_lsu_ctrl_o  = lsu_ctrl;
  // Probe only: the translated address of the access currently presented to
  // the store buffer / AMO buffer. Pairing it with the access it belongs to is
  // done in cva6_rvfi.sv, no RVFI logic lives in the CPU RTL.
  assign rvfi_mem_paddr_o = mmu_paddr;

  //pragma translate_off
  // A load data trigger break goes with the load it matched, which leaves the
  // output register in the same cycle and carries it.
  sdtrig_load_data_on_its_load :
  assert property (@(posedge clk_i) disable iff (~rst_ni)
        (CVA6Cfg.SdtrigMcontrol6LoadData && sdtrig_load_data_action_i != '0)
        |-> (load_valid_o && !load_exception.valid && load_exception_o.timing))
  else $error("[load_store_unit] load data trigger break without the load it matched");
  //pragma translate_on

endmodule

