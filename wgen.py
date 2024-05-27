#
# Function: Wave Generator command compiler
# Ver: 1.2
# Author: Zack
#
import os, shutil, math
class Signal:
    def __init__(self, name:str,bits:int):
        self.name = name
        self.bits = bits
        self.val = ""
        self.maskmap = ""
    def __str__(self):
        s = f'Signal name bits maskmap = {self.name} {self.bits} {self.maskmap}'
        return s

class Wgen:
    ctrl_dict = {
        "drive":"0001",
        "wait":"0010",
        "drv_wait":"0011",
        "wait_drv":"0100",
        "jump":"1000",
        "nop":"0111",
        "repeat":"1000"
    }
    subctrl_dict = {
        "NORMAL" : '0000',
        "ADD" : "0001",
        "SUB" : "0010",
        "SHFL": "0011",
        "SHFR": "0100",
        "LFSR": "0101"
    }
    subctrl_wait_dict = {
        "EQUAL" : '0000',
        "LARGE" : '0001',
        "SMALL" : '0010',
        "LEQ"   : '0011',
        "SEQ"   : '0100',
        "NEQ"   : '0101'
    }
    
    def __init__(self, name:str):
        self.name = name
        self.op_txt = []
        self.op_bin = []
        self.out_signals = []
        self.out_bits = 0
        self.in_signals = []
        self.in_bits = 0
        self.max_bits = 0
        self.cfg = {}
        self.output_val = ""
        self.input_val = ""
        self.pad_asm = 0
        self.module_intf_str = ""
        self.module_connection_str = ""
        self.module_str = ""
        self.module_tb_intf_str = ""
        self.module_tb_connection_str = ""
        self.module_tb_str = ""

    def __str__(self):
        return f'{self.name}'

    def config(self, cfg:dict):
        self.cfg = cfg
        out_sig_dict = {}
        in_sig_dict = {}
        if "output" in cfg:
            out_sig_dict = cfg["output"]
        else:
            print("Error: output must define")
        if "input" in cfg:
            in_sig_dict = cfg["input"]
        for sig in out_sig_dict:
            name = sig
            bits = out_sig_dict[name]
            signal = Signal(name, bits)
            self.out_signals.insert(0, signal)
            self.out_bits += signal.bits
        for sig in in_sig_dict:
            name = sig
            bits = in_sig_dict[name]
            signal = Signal(name, bits)
            self.in_signals.insert(0, signal)
            self.in_bits += signal.bits
        if self.out_bits > self.in_bits:
            self.max_bits = self.out_bits
        else:
            self.max_bits = self.in_bits
        for s in self.out_signals:
            s.maskmap = s.maskmap.zfill(self.out_bits)
            s_n, e_n = self.get_sig_range(s.name, "o")
            s.maskmap = "1"*len(s.maskmap)
            s.maskmap = s.maskmap[0:s_n] + "0"*(e_n-s_n) + s.maskmap[e_n:]
            s.maskmap = s.maskmap[::-1]
            s.maskmap = s.maskmap.rjust(self.max_bits, "1")
            #print("debug ", s.maskmap, s_n,e_n,s.name)
        for s in self.in_signals:
            s.maskmap = s.maskmap.zfill(self.in_bits)
            s_n, e_n = self.get_sig_range(s.name, "i")
            s.maskmap = "1"*len(s.maskmap)
            s.maskmap = s.maskmap[0:s_n] + "0"*(e_n-s_n) + s.maskmap[e_n:]
            s.maskmap = s.maskmap[::-1]
            s.maskmap = s.maskmap.rjust(self.max_bits, "1")
            #print("debug ", s.maskmap, s_n, e_n, s.name)
        self.output_val = self.output_val.zfill(self.max_bits)
        self.input_val = self.input_val.zfill(self.max_bits)
        self.pkg_dir = self.cfg['name']+'_pkg/'
        self.module_name = self.cfg['name']
        if os.path.exists(self.pkg_dir):
            ret = shutil.rmtree(self.pkg_dir)
            if ret:
                print(f"Error: rm dir {self.pkg_dir} failed, ret={ret}")
        ret = os.mkdir(self.pkg_dir)
        if os.path.exists("wgen.sv"):
            shutil.copy("wgen.sv", self.pkg_dir)
        if ret:
            print(f"Error: make dir {self.pkg_dir} failed, ret={ret}")
        return
    def get_sig_range(self, sig:str, io="o"):
        signal, idx = self.get_sig(sig, io)
        nbits = 0
        start_bitn = 0
        end_bitn = 0
        if signal:
            if io=="o":
                for i, s in enumerate(self.out_signals):
                    if i==idx:
                        break
                    nbits += s.bits
                start_bitn = nbits
                end_bitn = nbits + signal.bits;
            else:
                for i, s in enumerate(self.in_signals):
                    if i == idx:
                        break
                    nbits += s.bits
                start_bitn = nbits
                end_bitn = nbits + signal.bits;
        return start_bitn,end_bitn
    def get_sig(self, sig: str, io="o"):
        signal = None
        n = 0
        sig = sig.strip()
        if io=="o":
            for sig_ in self.out_signals:
                if sig_.name==sig:
                    signal = sig_
                    break;
                n += 1
        else:
            for sig_ in self.in_signals:
                if sig_.name==sig:
                    signal = sig_
                    break;
                n += 1
        if not signal:
            print(f"Error: {sig} not found")
        return signal,n

    def hex2bin(self, h:str):
        bs = ""
        for c in h:
            num = int(c, 16)
            bc = bin(num)[2:]
            bc = bc.zfill(4)
            bs = bs + bc
        index = bs.find("1")
        if index != "-1":
            bs = bs[index:]
        return bs
    def int2bin(self, i:str):
        i_ = i
        if i[0]=="d":
            i_ = i[1:]
        return bin(num)[2:]
    def bin_and(self,b1:str,b2:str):
        new_bin = ""
        for i in range(len(b1)):
            if b1[i]=="0" or b2[i]=="0":
                new_bin += "0"
            else:
                new_bin += "1"
        return  new_bin
    def bin2hex(self, b):
        m = len(b) % 4
        l = len(b)
        if m:
            l = l + 4 - m
        b2 = b.zfill(l)
        n = len(b2) // 4
        hs = ""
        for i in range(n):
            b4 = b2[i * 4: i * 4 + 4]
            ii = int(b4, 2)
            h = hex(ii)[2:]
            h = h.upper()
            hs = hs + h
        return hs
    def data2bin(self, data:str):
        ft = ""
        d = data
        db = ""
        if data[0:2]=="0x":
            ft = "hex"
            d = data[2:]
        elif data[0]=="h":
            ft = "hex"
            d = data[1:]
        elif data[0]=="b":
            ft = "bin"
            d = data[1:]
        elif data[0]=="d":
            ft = "dec"
            d = data[1:]
        else:
            ft = "dec"
            d = data
        if ft=="hex":
            db = self.hex2bin(d)
        elif ft=="dec":
            db = bin(int(d))[2:]
        elif ft=="bin":
            db = d
        return db

    def set_sigval(self, sig:str, data:str, io="o"):
        #note, all the value are string type, to support hex, bin, dec formal. 0x1234/h1234, b0011, d123/123
        #convert to binary, do process, convert target format
        db = self.data2bin(data)
        if io=="o":
            if sig=="output":
                self.output_val = db.zfill(self.max_bits)
            else:
                start_n, end_n = self.get_sig_range(sig)
                #print("debug,out0: start_n, end_n, output_val, db", start_n, end_n, self.output_val, db)
                if end_n:
                    self.output_val = self.output_val[0: self.max_bits-end_n] + db.zfill(end_n-start_n)[0:end_n-start_n] + self.output_val[self.max_bits-start_n:self.max_bits]
                    #print("debug,out1: start_n, end_n, output_val, db", start_n, end_n, self.output_val, db)
        else:
            if sig=="input":
                self.input_val = db.zfill(self.max_bits)
            else:
                start_n, end_n = self.get_sig_range(sig,"i")
                if end_n:
                    self.input_val = self.input_val[0: self.max_bits-end_n] + db.zfill(end_n-start_n)[0:end_n-start_n] + self.input_val[self.max_bits-start_n:self.max_bits]

    def drive_t(self, sig:str, data:str='', subctrl="NORMAL", mask:str="0", task_name:str="drive", patch_str:str=""):
        #print(f"debug: drive {sig} {data} {mask} {subctrl}")
        ctrl_header = self.ctrl_dict[task_name] + self.subctrl_dict[subctrl]
        if sig!="output":
            anded_mask = "".rjust(self.max_bits, "1")
            if "," in sig:
                sig_list = sig.split(",")
                data_list = data.split(",")
                #print("debug, sig_list, data_list", sig_list, data_list)
                for i, sub_sig in enumerate(sig_list):
                    self.set_sigval(sig_list[i].strip(), data_list[i].strip())
                    signal, _= self.get_sig(sub_sig.strip())
                    anded_mask = self.bin_and(anded_mask, signal.maskmap)
            else:
                signal, n_ = self.get_sig(sig)
                self.set_sigval(sig, data)
            if subctrl=="NORMAL":
                op_t = f'{task_name}{patch_str}({sig}, {data})'
            else:
                op_t = f'{task_name}{patch_str}({sig}, {data}, {subctrl})'  #FIXME
                if "," in sig:
                    print("Error: non-NORMAL subctrl, dont support multi signals")
            if "," in sig:
                op_b = ctrl_header + anded_mask + self.output_val
            else:
                op_b = ctrl_header + signal.maskmap + self.output_val
        else:
            if data=='':
                op_t = f'{task_name}{patch_str}(output, {self.bin2hex(self.output_val)}{patch_str})'
                op_b = ctrl_header  + mask.zfill(self.max_bits) + self.output_val
            else:
                self.set_sigval(sig, data)
                op_t = f'{task_name}{patch_str}(output, {self.bin2hex(self.output_val)}, {mask}, {subctrl}{patch_str})'
                op_b = ctrl_header  + mask.zfill(self.max_bits) + self.output_val

        if self.pad_asm:
            op_t += " \t//" + self.bin2hex(op_b) #pad asm
        self.op_txt.append(op_t)
        self.op_bin.append(self.bin2hex(op_b)) #
        return len(self.op_bin) - 1

    def drv_wait_t(self, sig:str, data:str='', sig_wait:str="", data_wait:str="", subctrl:str="NORMAL", mask:str="0", subctrl_wait:str="EQUAL"):
        #to test more
        self.drive_t(sig, data, subctrl, mask, "drv_wait", ":drive")
        n = self.wait_t(sig_wait, data_wait, 0, "drv_wait", ":wait", subctrl_wait)
        return  n

    def wait_t(self, sig:str,data:str,mask:str="0", task_name:str="wait", patch_str="", subctrl:str="EQUAL"):
        ctrl_header = self.ctrl_dict[task_name] + self.subctrl_wait_dict[subctrl]
        if sig != "input":
            signal, n_ = self.get_sig(sig, "i")
            self.set_sigval(sig, data, "i")
            op_t = f'{task_name}{patch_str}({sig}, {data})'
            op_b = ctrl_header  + signal.maskmap + self.input_val
        else:
            op_t = f'{task_name}{patch_str}(input, {data}, {mask})'
            op_b = ctrl_header + mask + self.input_val
        if self.pad_asm:
            op_t += " \t//" + self.bin2hex(op_b) #pad asm
        self.op_txt.append(op_t)
        self.op_bin.append(self.bin2hex(op_b))  #
        return len(self.op_bin)-1

    def wait_drv_t(self, sig: str, data: str, sig_drv: str, data_drv: str = '', mask: str = "0", mask_drv: str = "0", subctrl: str = "NORMAL", subctrl_wait:str="EQUAL"):
        self.wait_t(sig, data, mask, "wait_drv", ":wait", subctrl_wait)
        self.drive_t(sig_drv, data_drv, subctrl, mask_drv, "wait_drv",":drive")
        return len(self.op_bin) - 1

    def repeat_t(self, times, start, end=0):
        #according to start and end , generate repeat op, insert to op_txt
        end = len(self.op_bin)-1 #override it
        #print(f"debug: repeat {times} {start} {end} {len(self.op_txt)-1}")
        ctrl_header = self.ctrl_dict["repeat"] + self.subctrl_dict["NORMAL"]
        times-=1 #ensure times>1, if times=1, discard it
        if times>0:
            backsteps = end-start+1; #repeat
            op_t = f'repeat({times}, {backsteps})'
        else:
            backsteps = start; #jump
            op_t = f'jump({start})'
        self.op_txt.append(op_t) #insert after the end op
        op_b = ctrl_header + bin(times)[2:].zfill(self.max_bits) + bin(backsteps)[2:].zfill(self.max_bits)
        self.op_bin.append(self.bin2hex(op_b))  #
        return len(self.op_bin)-1

    def jump_t(self, offset):
        self.repeat_t(1, offset)

    def nop_t(self, times=1):
        #according to start and end , generate repeat op, insert to op_txt
        ctrl_header = self.ctrl_dict["nop"] + self.subctrl_dict["NORMAL"]
        op_t = f'nop({times})'
        self.op_txt.append(op_t)
        op_b = ctrl_header + "".zfill(self.max_bits) + bin(times)[2:].zfill(self.max_bits)
        self.op_bin.append(self.bin2hex(op_b))  #
        return len(self.op_bin)-1

    def gen_op(self):
        op_txt_fname = self.pkg_dir + self.module_name+"_op.txt"
        op_bin_fname = self.pkg_dir + self.module_name+"_ram.txt"
        fop_txt = open(op_txt_fname, 'w', encoding='utf-8')
        if fop_txt:
            for op_t in self.op_txt:
                #print(op_t)
                fop_txt.write(op_t+"\n")
            print(f"{op_txt_fname} is generated successfully!")
        fop_bin = open(op_bin_fname, 'w', encoding='utf-8')
        if fop_bin:
            for op_b in self.op_bin:
                #print(op_b)
                fop_bin.write(op_b + "\n")
            nop_op = "01110000"+"".zfill(self.max_bits*2)
            nop_op = self.bin2hex(nop_op)
            for i in range(3):
                fop_bin.write(f"{nop_op}\n")
            fop_bin.write(f"0\n")
            print(f"{op_bin_fname} is generated successfully!")
        fop_txt.close()
        fop_bin.close()

    def selfcheck(self):
        #simulate op run, assume wait latency=0
        return

    def gen_module(self):
        intf_str = ""
        conn_str = ""
        intf_str += "  //output signals\n"
        conn_str += "//output connection\n"
        nidx = 0
        for o_sig in self.out_signals:
            nbit = o_sig.bits
            nidx_msb = nidx + nbit -1
            nidx_lsb = nidx
            if nbit>1:
                line = f"  output logic [{nbit-1} : 0] {o_sig.name},\n"
            else:
                line = f'  output logic {o_sig.name},\n'
            intf_str += line
            line2 = f'assign {o_sig.name} = out_sig[{nidx_msb} : {nidx_lsb}];\n'
            nidx += nbit
            conn_str += line2

        intf_str += "  //input signals\n"
        conn_str += "//input connection\n"
        nidx = 0
        for i_sig in self.in_signals:
            nbit = i_sig.bits
            nidx_msb = nidx + nbit -1
            nidx_lsb = nidx
            if nbit>1:
                line = f"  input logic [{nbit-1} : 0] {i_sig.name},\n"
            else:
                line = f'  input logic {i_sig.name},\n'
            intf_str += line
            line2 = f'assign in_sig[{nidx_msb} : {nidx_lsb}] = {i_sig.name} ;\n'
            nidx += nbit
            conn_str += line2
        self.module_intf_str = intf_str
        self.module_connection_str = conn_str
        self.module_str = f'''
/*
This file is generated by wgen.py .
*/
`timescale 1ns/1ps
module  {self.module_name} 
(
  input logic clk,
  input logic rst_n,
  input logic enable,

{self.module_intf_str}
`ifdef RAM_WINF
  //ram write interface
  input logic [{self.max_bits}-1 : 0] ram_wdata,
  input logic [{math.ceil(math.log2(self.cfg["ram_depth"]))} - 1:0] ram_waddr,
  input logic ram_wen,
`endif
  //debug
  output logic [7:0] status
);
logic [{self.max_bits}-1 : 0] in_sig, out_sig;
wgen #(.wrl({self.max_bits}), .depth({self.cfg["ram_depth"]}), .ring_depth({self.cfg["ring_depth"]})) wgen(.*);
{self.module_connection_str}
endmodule
'''
        module_fname = self.pkg_dir + self.module_name+".sv"
        fmodule = open(module_fname, 'w', encoding='utf-8')
        if fmodule:
            fmodule.write(self.module_str)
            print(f"{module_fname} is generated successfully!")
        fmodule.close()

    def gen_module_tb(self):
        intf_str = ""
        intf_str += "  //output signals\n"
        for o_sig in self.out_signals:
            nbit = o_sig.bits
            if nbit>1:
                line = f"  logic [{nbit-1} : 0] {o_sig.name};\n"
            else:
                line = f'  logic {o_sig.name};\n'
            intf_str += line

        intf_str += "  //input signals\n"
        for i_sig in self.in_signals:
            nbit = i_sig.bits
            if nbit>1:
                line = f"  logic [{nbit-1} : 0] {i_sig.name};\n"
            else:
                line = f'  logic {i_sig.name};\n'
            intf_str += line
        conn_str = "//init input to 1 (single bit) and 0 (multi bit)\n"
        conn_str += "  initial begin\n"
        for i_sig in self.in_signals:
            nbit = i_sig.bits
            if nbit>1:
                line = f"  {i_sig.name}[{nbit-1} : 0] = 'b0;\n"
            else:
                line = f"  {i_sig.name} = 'b1;\n"
            conn_str += line
        conn_str += "  end\n"
        self.module_tb_intf_str = intf_str
        self.module_tb_connection_str = conn_str
        self.module_tb_str = f'''
/*
This file is generated by wgen.py .
*/
`timescale 1ns/1ps
module  {self.module_name+"_tb"};
logic clk,rst_n,enable;
logic [7:0] status;
`ifdef RAM_WINF
//ram write interface
logic [{self.max_bits}-1 : 0] ram_wdata;
logic [{math.ceil(math.log2(self.cfg["ram_depth"]))} - 1:0] ram_waddr;
logic ram_wen;
initial begin
  ram_wdata <= 0;
  ram_waddr <= 0;
  ram_wen <= 0;
end
`endif
{self.module_tb_intf_str}
{self.module_name} {self.module_name}(.*);
{self.module_tb_connection_str}
  initial begin
    clk = 'b0;
    rst_n = 'b0;
    enable = 'b0;
    while(1) begin
      #5;
      clk = ~clk;
    end
  end
  initial begin
    repeat(2) @(posedge clk);
    rst_n = 'b1;
    enable = 'b1;
  end
  initial begin
    int tmo = 1000;
    $value$plusargs("tmo=%0d",tmo);
    repeat(tmo) begin
      @(posedge clk);
    end
    $finish();
  end
  initial begin
    $readmemh("{self.module_name}_ram.txt", {self.module_name}.wgen.ram);
    $vcdpluson();
  end
endmodule
'''
        module_tb_fname = self.pkg_dir + self.module_name+"_tb.sv"
        fmodule_tb = open(module_tb_fname, 'w', encoding='utf-8')
        if fmodule_tb:
            fmodule_tb.write(self.module_tb_str)
            print(f"{module_tb_fname} is generated successfully!")
        fmodule_tb.close()

    def gen_makefile(self):
        mk_fname = self.pkg_dir + "Makefile"
        fmk = open(mk_fname, 'w', encoding='utf-8')
        self.mk_str = f'''
tmo ?= 1000
all: comp sim
comp:
    vcs -full64 -sverilog -debug_all {self.module_name}.sv {self.module_name}_tb.sv wgen.sv -l comp.log 
sim:
    ./simv -l sim.log +tmo=${{tmo}}
dve:    
    dve -full64 -vpd vcdplus.vpd &
run: sim

clean:
    rm -rf csrc *.log simv*         
        '''
        if fmk:
            fmk.write(self.mk_str)
            print(f"{mk_fname} is generated successfully!")
        fmk.close()
