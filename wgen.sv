/*
Function: Wave Generator, cycle cmd processor.
Ver: 1.4
Author: Zack
*/
`timescale 1ns/1ps
module wgen #(parameter wrl=32,depth=1024,ring_depth=256,ram_aw = $clog2(depth) ) (
input wire clk,
input wire rst_n,
input wire enable,
output reg [wrl-1:0] out_sig,
input wire [wrl-1:0] in_sig,
`ifdef RAM_WINF
input wire [ram_dw-1:0] ram_wdata,
input wire [ram_aw-1:0] ram_waddr,
input wire ram_wen,
`endif
output reg [7:0] status
);
//parameter ram_aw = $clog2(depth);
parameter buf_aw = $clog2(ring_depth);
parameter ctrl_w = 4;
parameter subctrl_w = 4;
parameter ram_dw = ctrl_w + subctrl_w + wrl + wrl; //ctrl+subctrl+msk+data
parameter END=4'b0000, WR = 4'b0001, RD = 4'b0010, WR_RD = 4'b0011, RD_WR = 4'b0100, NOP = 4'b0111, RP = 4'b1000;
parameter NORMAL=4'b0000, ADD = 4'b0001, SUB = 4'b0010, SHFL=4'b0011, SHFR=4'b0100, LFSR=4'b0101;
parameter EQUAL=4'b0000, LARGE = 4'b0001, SMALL = 4'b0010, LEQ = 4'b0011, SEQ = 4'b0100, NEQ = 4'b0101; //==, >, <, >=, <=, !=
parameter STACK_ADDR_WIDTH = 4;   // 
parameter end_code = 0; //end
parameter thrd_bufready = ring_depth/2, thrd_empty=2, thrd_full=4;

reg [ram_dw-1:0] ram[depth];
reg [ram_dw-1:0] ring_buf[ring_depth];

reg [ram_dw-1:0] d0,d1,d2,d3,op0,op1;
reg [ram_aw-1 : 0] bpc, bpc_saved; //bpc to point batch load
reg [buf_aw-1 : 0] wptr, rptr;
wire [buf_aw-1 : 0] wptr_p1, rptr_p1;
wire [buf_aw-1 : 0] wptr_p2, rptr_p2;
wire [buf_aw-1 : 0] wptr_p3, rptr_p3;
wire [buf_aw-1 : 0] wptr_p4, rptr_p4;
reg [ram_aw-1+1+wrl : 0] cnt0, cnt1, cnt2, cnt3; //to record RP [npc used cnt_val]
wire cond_cnt0, cond_cnt1, cond_cnt2, cond_cnt3;
reg wait_st, the_end, first_op_done, op0_read_done;
wire [subctrl_w-1:0] subctrl,subctrl_next;
wire [wrl-1:0] wmask,wdata,wmask_next,wdata_next,rmask,rdata,in_mask,rd_mask,in_mask_n,rd_mask_n,rmask_next,rdata_next,repeat_times,back_steps;
reg [wrl-1:0] out_sig_new, out_sig_new2;
reg almost_full, almost_empty;
reg buf_ready;
reg bpc_updated, read_ram_done, read_ram_start, read_ram_stop;
reg [47:0] wnum, rnum;
reg [wrl-1:0] nop_cnt, nop_val_saved;
wire [wrl-1:0] nop_val;
wire wait_cond, wait_cond_n;

assign cnt0_is_empty = ~cnt0[wrl];
assign cnt1_is_empty = ~cnt1[wrl];
assign cnt2_is_empty = ~cnt2[wrl];
assign cnt3_is_empty = ~cnt3[wrl];
assign rptr_p1 = rptr + 1;
assign rptr_p2 = rptr + 2;
assign rptr_p3 = rptr + 3;
assign rptr_p4 = rptr + 4;
assign wptr_p1 = wptr + 1;
assign wptr_p2 = wptr + 2;
assign wptr_p3 = wptr + 3;
assign wptr_p4 = wptr + 4;

wire [ctrl_w-1:0] ctrl0,ctrl1,ctrl2,ctrl3, ctrl_op0;
assign ctrl0 = d0[ram_dw-1 -: ctrl_w];
assign ctrl1 = d1[ram_dw-1 -: ctrl_w];
assign ctrl2 = d2[ram_dw-1 -: ctrl_w];
assign ctrl3 = d3[ram_dw-1 -: ctrl_w];
assign ctrl0_is_rp = ctrl0==RP? 1 : 0;
assign ctrl1_is_rp = ctrl1==RP? 1 : 0;
assign ctrl2_is_rp = ctrl2==RP? 1 : 0;
assign ctrl3_is_rp = ctrl3==RP? 1 : 0;
assign ctrl0_is_op = (ctrl0!=RP&&ctrl0!=END)? 1 : 0;
assign ctrl1_is_op = (ctrl1!=RP&&ctrl1!=END)? 1 : 0;
assign ctrl2_is_op = (ctrl2!=RP&&ctrl2!=END)? 1 : 0;
assign ctrl3_is_op = (ctrl3!=RP&&ctrl3!=END)? 1 : 0;
assign ctrl0_is_2op = (ctrl0==WR_RD || ctrl0==RD_WR) ? 1 : 0;
assign ctrl1_is_2op = (ctrl1==WR_RD || ctrl1==RD_WR) ? 1 : 0;
assign ctrl2_is_2op = (ctrl2==WR_RD || ctrl2==RD_WR) ? 1 : 0;
assign ctrl3_is_2op = (ctrl3==WR_RD || ctrl3==RD_WR) ? 1 : 0;
assign ctrl0_is_1op = (ctrl0==WR || ctrl0==RD || ctrl0==NOP) ? 1 : 0;
assign ctrl1_is_1op = (ctrl1==WR || ctrl1==RD || ctrl1==NOP) ? 1 : 0;
assign ctrl2_is_1op = (ctrl2==WR || ctrl2==RD || ctrl2==NOP) ? 1 : 0;
assign ctrl3_is_1op = (ctrl3==WR || ctrl3==RD || ctrl3==NOP) ? 1 : 0;

assign ctrl_op0 = op0[ram_dw-1 -: ctrl_w];
assign nop_val = op0[wrl-1:0];
assign subctrl=op0[ram_dw-ctrl_w-1 -: subctrl_w];
assign subctrl_next=op1[ram_dw-ctrl_w-1 -: subctrl_w];
assign wmask = op0[wrl*2 - 1 -: wrl];
assign wdata = op0[wrl-1 : 0 ];
assign wmask_next = op1[wrl*2 - 1 -: wrl];
assign wdata_next = op1[wrl-1 : 0 ];
assign rmask = op0[wrl*2 - 1 -: wrl];
assign rdata = op0[wrl-1 : 0 ];
assign rmask_next = op1[wrl*2 - 1 -: wrl];
assign rdata_next = op1[wrl-1 : 0 ];
assign out_sig_new = (out_sig&wmask) | ((~wmask) & ( subctrl==NORMAL? wdata&~wmask  : subctrl==ADD? (out_sig&~wmask)+(wdata&~wmask) : subctrl==SUB? (out_sig&~wmask)-(wdata&~wmask) : subctrl==SHFL? (out_sig&~wmask) << wdata : subctrl==SHFR? (out_sig&~wmask) >> wdata : subctrl==LFSR? {out_sig[wrl-2:0],out_sig[wrl-1]^out_sig[0]} : wdata )) ;
assign out_sig_new2 = (out_sig&wmask_next) | ((~wmask_next) & ( subctrl_next==NORMAL? wdata_next&~wmask_next  : subctrl_next==ADD? (out_sig&~wmask_next)+(wdata_next&~wmask_next) : subctrl_next==SUB? (out_sig&~wmask_next)-(wdata_next&~wmask_next) : subctrl_next==SHFL? (out_sig&~wmask_next) << wdata_next : subctrl_next==SHFR? (out_sig&~wmask_next) >> wdata_next : subctrl_next==LFSR? {out_sig[wrl-2:0],out_sig[wrl-1]^out_sig[0]} : wdata_next )) ;
assign in_mask = in_sig&~rmask;
assign rd_mask = rdata&~rmask;
assign wait_cond = ~(subctrl==EQUAL? in_mask==rd_mask : subctrl==LARGE? in_mask>rd_mask : subctrl==SMALL? in_mask<rd_mask : subctrl==LEQ? in_mask>=rd_mask : subctrl==SEQ? in_mask<=rd_mask : subctrl==NEQ? in_mask!=rd_mask : in_mask==rd_mask);
assign in_mask_n = in_sig&~rmask_next;
assign rd_mask_n = rdata_next&~rmask_next;
assign wait_cond_n = ~(subctrl_next==EQUAL? in_mask_n==rd_mask_n : subctrl_next==LARGE? in_mask_n>rd_mask_n : subctrl_next==SMALL? in_mask_n<rd_mask_n : subctrl_next==LEQ? in_mask_n>=rd_mask_n : subctrl_next==SEQ? in_mask_n<=rd_mask_n : subctrl_next==NEQ? in_mask_n!=rd_mask_n : in_mask_n==rd_mask_n);

assign cond_cnt0 = cnt0[ram_aw+wrl:wrl+1]!=bpc+0 && cnt1[ram_aw+wrl:wrl+1]!=bpc+0 && cnt2[ram_aw+wrl:wrl+1]!=bpc+0 && cnt3[ram_aw+wrl:wrl+1]!=bpc+0;
assign cond_cnt1 = cnt0[ram_aw+wrl:wrl+1]!=bpc+1 && cnt1[ram_aw+wrl:wrl+1]!=bpc+1 && cnt2[ram_aw+wrl:wrl+1]!=bpc+1 && cnt3[ram_aw+wrl:wrl+1]!=bpc+1;
assign cond_cnt2 = cnt0[ram_aw+wrl:wrl+1]!=bpc+2 && cnt1[ram_aw+wrl:wrl+1]!=bpc+2 && cnt2[ram_aw+wrl:wrl+1]!=bpc+2 && cnt3[ram_aw+wrl:wrl+1]!=bpc+2;
assign cond_cnt3 = cnt0[ram_aw+wrl:wrl+1]!=bpc+3 && cnt1[ram_aw+wrl:wrl+1]!=bpc+3 && cnt2[ram_aw+wrl:wrl+1]!=bpc+3 && cnt3[ram_aw+wrl:wrl+1]!=bpc+3;
//handle bpc and d0-3 load from ram
always @(posedge clk) begin
  if(~rst_n) begin
    bpc <= 0;
    bpc_updated <= 'b1;
    read_ram_done <= 'b0;
    read_ram_start <= 'b0;
    read_ram_stop <= 'b0;
    d0 <= 'b0;
    d1 <= 'b0;
    d2 <= 'b0;
    d3 <= 'b0;
    cnt0 <= 'b0;
    cnt1 <= 'b0;
    cnt2 <= 'b0;
    cnt3 <= 'b0;
  end else begin
  //handle counter for loop, and update bpc
  if(read_ram_done && ~almost_full && ~read_ram_stop) begin
    //register counter, and set cnt=1
    if(ctrl0_is_rp) begin
      if(d0[wrl*2 - 1 -: wrl]==0) begin
        bpc <= bpc + 0 + d0[wrl-1 : 0];
      end else begin //jump
           if(cnt0_is_empty && cond_cnt0) begin cnt0[wrl] <=1; cnt0[wrl-1:0] <=1; cnt0[ram_aw+wrl:wrl+1] <=bpc+0; bpc <= bpc + 0 - d0[wrl-1 : 0];end
      else if(cnt1_is_empty && cond_cnt0) begin cnt1[wrl] <=1; cnt1[wrl-1:0] <=1; cnt1[ram_aw+wrl:wrl+1] <=bpc+0; bpc <= bpc + 0 - d0[wrl-1 : 0];end
      else if(cnt2_is_empty && cond_cnt0) begin cnt2[wrl] <=1; cnt2[wrl-1:0] <=1; cnt2[ram_aw+wrl:wrl+1] <=bpc+0; bpc <= bpc + 0 - d0[wrl-1 : 0];end
      else if(cnt3_is_empty && cond_cnt0) begin cnt3[wrl] <=1; cnt3[wrl-1:0] <=1; cnt3[ram_aw+wrl:wrl+1] <=bpc+0; bpc <= bpc + 0 - d0[wrl-1 : 0];end
      end //repeat
    end else
    if(ctrl1_is_rp) begin
      if(d1[wrl*2 - 1 -: wrl]==0) begin
        bpc <= bpc + 1 + d1[wrl-1 : 0];
      end else begin //jump
           if(cnt0_is_empty && cond_cnt1) begin cnt0[wrl] <=1; cnt0[wrl-1:0] <=1; cnt0[ram_aw+wrl:wrl+1] <=bpc+1; bpc <= bpc + 1 - d1[wrl-1 : 0];end
      else if(cnt1_is_empty && cond_cnt1) begin cnt1[wrl] <=1; cnt1[wrl-1:0] <=1; cnt1[ram_aw+wrl:wrl+1] <=bpc+1; bpc <= bpc + 1 - d1[wrl-1 : 0];end
      else if(cnt2_is_empty && cond_cnt1) begin cnt2[wrl] <=1; cnt2[wrl-1:0] <=1; cnt2[ram_aw+wrl:wrl+1] <=bpc+1; bpc <= bpc + 1 - d1[wrl-1 : 0];end
      else if(cnt3_is_empty && cond_cnt1) begin cnt3[wrl] <=1; cnt3[wrl-1:0] <=1; cnt3[ram_aw+wrl:wrl+1] <=bpc+1; bpc <= bpc + 1 - d1[wrl-1 : 0];end
      end //repeat
    end else
    if(ctrl2_is_rp) begin
      if(d2[wrl*2 - 1 -: wrl]==0) begin
        bpc <= bpc + 2 + d2[wrl-1 : 0];
      end else begin //jump
           if(cnt0_is_empty && cond_cnt2) begin cnt0[wrl] <=1; cnt0[wrl-1:0] <=1; cnt0[ram_aw+wrl:wrl+1] <=bpc+2; bpc <= bpc + 2 - d2[wrl-1 : 0];end
      else if(cnt1_is_empty && cond_cnt2) begin cnt1[wrl] <=1; cnt1[wrl-1:0] <=1; cnt1[ram_aw+wrl:wrl+1] <=bpc+2; bpc <= bpc + 2 - d2[wrl-1 : 0];end
      else if(cnt2_is_empty && cond_cnt2) begin cnt2[wrl] <=1; cnt2[wrl-1:0] <=1; cnt2[ram_aw+wrl:wrl+1] <=bpc+2; bpc <= bpc + 2 - d2[wrl-1 : 0];end
      else if(cnt3_is_empty && cond_cnt2) begin cnt3[wrl] <=1; cnt3[wrl-1:0] <=1; cnt3[ram_aw+wrl:wrl+1] <=bpc+2; bpc <= bpc + 2 - d2[wrl-1 : 0];end
      end //repeat
    end else
    if(ctrl3_is_rp) begin
      if(d3[wrl*2 - 1 -: wrl]==0) begin
        bpc <= bpc + 3 + d3[wrl-1 : 0];
      end else begin //jump
           if(cnt0_is_empty && cond_cnt3) begin cnt0[wrl] <=1; cnt0[wrl-1:0] <=1; cnt0[ram_aw+wrl:wrl+1] <=bpc+3; bpc <= bpc + 3 - d3[wrl-1 : 0];end
      else if(cnt1_is_empty && cond_cnt3) begin cnt1[wrl] <=1; cnt1[wrl-1:0] <=1; cnt1[ram_aw+wrl:wrl+1] <=bpc+3; bpc <= bpc + 3 - d3[wrl-1 : 0];end
      else if(cnt2_is_empty && cond_cnt3) begin cnt2[wrl] <=1; cnt2[wrl-1:0] <=1; cnt2[ram_aw+wrl:wrl+1] <=bpc+3; bpc <= bpc + 3 - d3[wrl-1 : 0];end
      else if(cnt3_is_empty && cond_cnt3) begin cnt3[wrl] <=1; cnt3[wrl-1:0] <=1; cnt3[ram_aw+wrl:wrl+1] <=bpc+3; bpc <= bpc + 3 - d3[wrl-1 : 0];end
      end //repeat
    end
         //counter ++
    if(ctrl0_is_rp) begin
               if(~cnt0_is_empty && cnt0[ram_aw+wrl:wrl+1]==bpc+0 && cnt0[wrl-1:0]<d0[wrl*2 - 1 -: wrl]) begin
        cnt0[wrl-1:0] <= cnt0[wrl-1:0] + 1;
        bpc <= bpc + 0 - d0[wrl-1 : 0];
      end else if(~cnt1_is_empty && cnt1[ram_aw+wrl:wrl+1]==bpc+0 && cnt1[wrl-1:0]<d0[wrl*2 - 1 -: wrl]) begin
        cnt1[wrl-1:0] <= cnt1[wrl-1:0] + 1;
        bpc <= bpc + 0 - d0[wrl-1 : 0];
      end else if(~cnt2_is_empty && cnt2[ram_aw+wrl:wrl+1]==bpc+0 && cnt2[wrl-1:0]<d0[wrl*2 - 1 -: wrl]) begin
        cnt2[wrl-1:0] <= cnt2[wrl-1:0] + 1;
        bpc <= bpc + 0 - d0[wrl-1 : 0];
      end else if(~cnt3_is_empty && cnt3[ram_aw+wrl:wrl+1]==bpc+0 && cnt3[wrl-1:0]<d0[wrl*2 - 1 -: wrl]) begin
        cnt3[wrl-1:0] <= cnt3[wrl-1:0] + 1;
        bpc <= bpc + 0 - d0[wrl-1 : 0];
      end //reset counter when count done
      else     if(~cnt0_is_empty && cnt0[ram_aw+wrl:wrl+1]==bpc+0 && cnt0[wrl-1:0]==d0[wrl*2 - 1 -: wrl]) begin
        cnt0 <= 0;
        bpc <= bpc + 1 ;
      end else if(~cnt1_is_empty && cnt1[ram_aw+wrl:wrl+1]==bpc+0 && cnt1[wrl-1:0]==d0[wrl*2 - 1 -: wrl]) begin
        cnt1 <= 0;
        bpc <= bpc + 1 ;
      end else if(~cnt2_is_empty && cnt2[ram_aw+wrl:wrl+1]==bpc+0 && cnt2[wrl-1:0]==d0[wrl*2 - 1 -: wrl]) begin
        cnt2 <= 0;
        bpc <= bpc + 1 ;
      end else if(~cnt3_is_empty && cnt3[ram_aw+wrl:wrl+1]==bpc+0 && cnt3[wrl-1:0]==d0[wrl*2 - 1 -: wrl]) begin
        cnt3 <= 0;
        bpc <= bpc + 1 ;
      end
    end else
    if(ctrl1_is_rp) begin
               if(~cnt0_is_empty && cnt0[ram_aw+wrl:wrl+1]==bpc+1 && cnt0[wrl-1:0]<d1[wrl*2 - 1 -: wrl]) begin
        cnt0[wrl-1:0] <= cnt0[wrl-1:0] + 1;
        bpc <= bpc + 1 - d1[wrl-1 : 0];
      end else if(~cnt1_is_empty && cnt1[ram_aw+wrl:wrl+1]==bpc+1 && cnt1[wrl-1:0]<d1[wrl*2 - 1 -: wrl]) begin
        cnt1[wrl-1:0] <= cnt1[wrl-1:0] + 1;
        bpc <= bpc + 1 - d1[wrl-1 : 0];
      end else if(~cnt2_is_empty && cnt2[ram_aw+wrl:wrl+1]==bpc+1 && cnt2[wrl-1:0]<d1[wrl*2 - 1 -: wrl]) begin
        cnt2[wrl-1:0] <= cnt2[wrl-1:0] + 1;
        bpc <= bpc + 1 - d1[wrl-1 : 0];
      end else if(~cnt3_is_empty && cnt3[ram_aw+wrl:wrl+1]==bpc+1 && cnt3[wrl-1:0]<d1[wrl*2 - 1 -: wrl]) begin
        cnt3[wrl-1:0] <= cnt3[wrl-1:0] + 1;
        bpc <= bpc + 1 - d1[wrl-1 : 0];
      end //reset counter when count done
      else     if(~cnt0_is_empty && cnt0[ram_aw+wrl:wrl+1]==bpc+1 && cnt0[wrl-1:0]==d1[wrl*2 - 1 -: wrl]) begin
        cnt0 <= 0;
        bpc <= bpc + 2 ;
      end else if(~cnt1_is_empty && cnt1[ram_aw+wrl:wrl+1]==bpc+1 && cnt1[wrl-1:0]==d1[wrl*2 - 1 -: wrl]) begin
        cnt1 <= 0;
        bpc <= bpc + 2 ;
      end else if(~cnt2_is_empty && cnt2[ram_aw+wrl:wrl+1]==bpc+1 && cnt2[wrl-1:0]==d1[wrl*2 - 1 -: wrl]) begin
        cnt2 <= 0;
        bpc <= bpc + 2 ;
      end else if(~cnt3_is_empty && cnt3[ram_aw+wrl:wrl+1]==bpc+1 && cnt3[wrl-1:0]==d1[wrl*2 - 1 -: wrl]) begin
        cnt3 <= 0;
        bpc <= bpc + 2 ;
      end
    end else
    if(ctrl2_is_rp) begin
               if(~cnt0_is_empty && cnt0[ram_aw+wrl:wrl+1]==bpc+2 && cnt0[wrl-1:0]<d2[wrl*2 - 1 -: wrl]) begin
        cnt0[wrl-1:0] <= cnt0[wrl-1:0] + 1;
        bpc <= bpc + 2 - d2[wrl-1 : 0];
      end else if(~cnt1_is_empty && cnt1[ram_aw+wrl:wrl+1]==bpc+2 && cnt1[wrl-1:0]<d2[wrl*2 - 1 -: wrl]) begin
        cnt1[wrl-1:0] <= cnt1[wrl-1:0] + 1;
        bpc <= bpc + 2 - d2[wrl-1 : 0];
      end else if(~cnt2_is_empty && cnt2[ram_aw+wrl:wrl+1]==bpc+2 && cnt2[wrl-1:0]<d2[wrl*2 - 1 -: wrl]) begin
        cnt2[wrl-1:0] <= cnt2[wrl-1:0] + 1;
        bpc <= bpc + 2 - d2[wrl-1 : 0];
      end else if(~cnt3_is_empty && cnt3[ram_aw+wrl:wrl+1]==bpc+2 && cnt3[wrl-1:0]<d2[wrl*2 - 1 -: wrl]) begin
        cnt3[wrl-1:0] <= cnt3[wrl-1:0] + 1;
        bpc <= bpc + 2 - d2[wrl-1 : 0];
      end //reset counter when count done
      else     if(~cnt0_is_empty && cnt0[ram_aw+wrl:wrl+1]==bpc+2 && cnt0[wrl-1:0]==d2[wrl*2 - 1 -: wrl]) begin
        cnt0 <= 0;
        bpc <= bpc + 3 ;
      end else if(~cnt1_is_empty && cnt1[ram_aw+wrl:wrl+1]==bpc+2 && cnt1[wrl-1:0]==d2[wrl*2 - 1 -: wrl]) begin
        cnt1 <= 0;
        bpc <= bpc + 3 ;
      end else if(~cnt2_is_empty && cnt2[ram_aw+wrl:wrl+1]==bpc+2 && cnt2[wrl-1:0]==d2[wrl*2 - 1 -: wrl]) begin
        cnt2 <= 0;
        bpc <= bpc + 3 ;
      end else if(~cnt3_is_empty && cnt3[ram_aw+wrl:wrl+1]==bpc+2 && cnt3[wrl-1:0]==d2[wrl*2 - 1 -: wrl]) begin
        cnt3 <= 0;
        bpc <= bpc + 3 ;
      end
    end else
    if(ctrl3_is_rp) begin
               if(~cnt0_is_empty && cnt0[ram_aw+wrl:wrl+1]==bpc+3 && cnt0[wrl-1:0]<d3[wrl*2 - 1 -: wrl]) begin
        cnt0[wrl-1:0] <= cnt0[wrl-1:0] + 1;
        bpc <= bpc + 3 - d3[wrl-1 : 0];
      end else if(~cnt1_is_empty && cnt1[ram_aw+wrl:wrl+1]==bpc+3 && cnt1[wrl-1:0]<d3[wrl*2 - 1 -: wrl]) begin
        cnt1[wrl-1:0] <= cnt1[wrl-1:0] + 1;
        bpc <= bpc + 3 - d3[wrl-1 : 0];
      end else if(~cnt2_is_empty && cnt2[ram_aw+wrl:wrl+1]==bpc+3 && cnt2[wrl-1:0]<d3[wrl*2 - 1 -: wrl]) begin
        cnt2[wrl-1:0] <= cnt2[wrl-1:0] + 1;
        bpc <= bpc + 3 - d3[wrl-1 : 0];
      end else if(~cnt3_is_empty && cnt3[ram_aw+wrl:wrl+1]==bpc+3 && cnt3[wrl-1:0]<d3[wrl*2 - 1 -: wrl]) begin
        cnt3[wrl-1:0] <= cnt3[wrl-1:0] + 1;
        bpc <= bpc + 3 - d3[wrl-1 : 0];
      end //reset counter when count done
      else     if(~cnt0_is_empty && cnt0[ram_aw+wrl:wrl+1]==bpc+3 && cnt0[wrl-1:0]==d3[wrl*2 - 1 -: wrl]) begin
        cnt0 <= 0;
        bpc <= bpc + 4 ;
      end else if(~cnt1_is_empty && cnt1[ram_aw+wrl:wrl+1]==bpc+3 && cnt1[wrl-1:0]==d3[wrl*2 - 1 -: wrl]) begin
        cnt1 <= 0;
        bpc <= bpc + 4 ;
      end else if(~cnt2_is_empty && cnt2[ram_aw+wrl:wrl+1]==bpc+3 && cnt2[wrl-1:0]==d3[wrl*2 - 1 -: wrl]) begin
        cnt2 <= 0;
        bpc <= bpc + 4 ;
      end else if(~cnt3_is_empty && cnt3[ram_aw+wrl:wrl+1]==bpc+3 && cnt3[wrl-1:0]==d3[wrl*2 - 1 -: wrl]) begin
        cnt3 <= 0;
        bpc <= bpc + 4 ;
      end
    end else begin
        bpc <= bpc + 4 ;
    end
    bpc_updated <= 1;
    read_ram_done <= 0;
  end //read_ram_done & ~almost_full & ~the_end

  if(bpc_updated) begin
    read_ram_done <= 1;
    read_ram_start <= 'b1;
    bpc_updated <= 0;
    if((d0==end_code|d1==end_code|d2==end_code|d3==end_code)&&((cnt0|cnt1|cnt2|cnt3)==0)&&read_ram_start) begin
      read_ram_stop <= wnum>=thrd_bufready? 'b1 : 0; //pad 0 when not fill buf
      d0 <= 0;
      d1 <= 0;
      d2 <= 0;
      d3 <= 0;
    end else begin
      d0 <= ram[bpc];
      d1 <= ram[bpc+1];
      d2 <= ram[bpc+2];
      d3 <= ram[bpc+3];
    end
  end
  end //~rst_n
end

//handle push to ring buffer
always @(posedge clk) begin
  if(~rst_n) begin
    wptr <= 'b0;
    wnum <= 'h0;
    buf_ready <= 'b0;
  end else begin
  if(wptr>=thrd_bufready) buf_ready<='b1;
  /*
  */
  if(read_ram_done && ~read_ram_stop) begin
      if(~almost_full ) begin //if almost_full, hold push, wait rnum++
        if(ctrl0_is_rp) begin
          //no push
        end else
        if(ctrl1_is_rp) begin
          //push d0
          ring_buf[wptr+0] <= d0;
          wptr <= wptr + 'h1;
          wnum <= wnum + 'h1;
        end else
        if(ctrl2_is_rp) begin
          //push d0, d1
          ring_buf[wptr+0] <= d0;
          ring_buf[wptr_p1] <= d1;
          wptr <= wptr + 'h2;
          wnum <= wnum + 'h2;
        end else
        if(ctrl3_is_rp) begin
          //push d0, d1, d2
          ring_buf[wptr+0] <= d0;
          ring_buf[wptr_p1] <= d1;
          ring_buf[wptr_p2] <= d2;
          wptr <= wptr + 'h3;
          wnum <= wnum + 'h3;
        end else begin
          //push d0, d1, d2,d3
          ring_buf[wptr+0] <= d0;
          ring_buf[wptr_p1] <= d1;
          ring_buf[wptr_p2] <= d2;
          ring_buf[wptr_p3] <= d3;
          wptr <= wptr + 'h4;
          wnum <= wnum + 'h4;
          //$display("here write d0=%h to wptr=%h", d0, wptr);
        end
      end
    end //
end //~rst_n
end //always

//read out from ring buffer
//handle op

always @(posedge clk) begin
  if(~rst_n) begin
    out_sig <= 'b0;
    wait_st <= 'b0;
    the_end <= 'b0;
    first_op_done <= 'b0;
    op0_read_done <= 'h0;
    rptr <= 'b0;
    rnum <= 'h0;
    op0 <= 'b0;
    op1 <= 'b0;
    nop_cnt <= 'h0;
    nop_val_saved <= 'h0;
  end else begin
    first_op_done <= (ctrl_op0!=RP&&ctrl_op0!=END) ? 'b1 : first_op_done;
    if(buf_ready && ~the_end && ~almost_empty) begin //if almost_empty, wait wnum++; may break wave!!!
        if(ctrl_op0==WR) begin
          out_sig <= out_sig_new;
          rptr <= rptr + 'b1;
          rnum <= rnum + 'h1;
          op0 <= ring_buf[rptr_p1];
          op1 <= ring_buf[rptr_p2];
        end else
        if(ctrl_op0==RD) begin
          if (wait_cond) begin
            wait_st <= 'b1;
          end else begin
            wait_st <= 'b0;
            rptr <= rptr + 'b1;
            rnum <= rnum + 'h1;
            op0 <= ring_buf[rptr_p1];
            op1 <= ring_buf[rptr_p2];
          end
        end else
        if(ctrl_op0==WR_RD) begin
          out_sig <= out_sig_new;
          if (wait_cond_n) begin
            wait_st <= 'h1;
          end else begin
            wait_st <= 'b0;
            rptr <= rptr + 'h2;
            rnum <= rnum + 'h2;
            //$display("debug, in wr_rd, wait_st<=0, rptr=%h, at %t", rptr, $time);
            op0 <= ring_buf[rptr_p2];
            op1 <= ring_buf[rptr_p3];
          end
        end else
        if(ctrl_op0==RD_WR) begin
          //$display("debug, ctrl_op0=4, in_sig=%h, rdata=%h, rmask=%h, bool=%b, at time=%t", in_sig, rdata, rmask, (in_sig&~rmask)!=(rdata&~rmask), $time);
          if (wait_cond) begin
            wait_st <= 'h1;
            //$display("debug, in rd_wr, wait_st<=1, rptr=%h, at %t", rptr, $time);
          end else begin
            wait_st <= 'b0;
            out_sig <= out_sig_new2;
            rptr <= rptr + 'h2;
            rnum <= rnum + 'h2;
            op0 <= ring_buf[rptr_p2];
            op1 <= ring_buf[rptr_p3];
            //$display("debug, in rd_wr, wait_st<=0, rptr=%h, at %t", rptr, $time);
            //dump_ring("rd_wr");
          end
        end else
        if(ctrl_op0==NOP) begin
          //do nothing
          if(nop_val==0 || nop_val==1 || nop_val-nop_cnt==1) begin
            wait_st <= 0;
            nop_cnt <= 0;
            rptr <= rptr + 'b1;
            rnum <= rnum + 'h1;
            op0 <= ring_buf[rptr_p1];
            op1 <= ring_buf[rptr_p2];
          end else begin
            wait_st <= 1;
            nop_cnt <= nop_cnt + 1;
          end
        end else
        if(op0==end_code) begin
          the_end <= first_op_done ? 'b1 : 'b0;
        end
    end//buf_ready
    else begin
        //first read op0
        if(wnum>0 && rptr==0 && ~op0_read_done) begin
          op0 <= ring_buf[rptr];
          op1 <= ring_buf[rptr_p1];
          op0_read_done <= 1;
        end
    end
  end //~rst_n
end //always

//status
always @(posedge clk) begin
  if(~rst_n) begin
    status <= 'h0;
    almost_full <= 0;
    almost_empty <= 0;
  end else begin
    status[0] <= read_ram_stop; //op read from ram done
    status[1] <= the_end ; //op run the end
    status[2] <= almost_empty;  //read is faster than write, underflow
    status[3] <= almost_full;  //write is fater
    status[4] <= bpc>depth/2 ;
    status[5] <= wait_st;
    almost_empty <= (rnum>=wnum || (rnum<wnum && wnum-rnum<thrd_empty))? (buf_ready ? 1 : 0) :0 ;
    almost_full <= (wnum>rnum&& ((wnum-rnum)>(ring_depth-thrd_full))) ? (buf_ready ? 1 : 0) :0 ;
  end
end
`ifdef RAM_WINF
always @(posedge clk) begin
  if(ram_wen) begin
    ram[ram_waddr] <= ram_wdata;
  end
end
`endif

`ifdef DEBUG_EN
task dump_ring(input string a="dump_ring");
for(int i=0;i<ring_depth;i=i+1) begin
  $display("debug_%s, ring_buf[%0d] = %h",a, i, ring_buf[i]);
end
endtask
task dump_ram(input string a="dump_ram");
for(int i=0;i<depth;i=i+1) begin
  $display("debug_%s, ram[%0d] = %h",a, i, ram[i]);
end
endtask
`endif


endmodule : wgen
