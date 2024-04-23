## Overview
wgen is a wave and stimulus generator. It can generate cycle by cycle wave and stimulus, through cmd. The kernal is a rtl engine written by verilog. 
It is synthesizable. Then we can use it in EDA, FPGA, and emulator. Share the same stimulus crossing 3 different platforms. 
It can generate as complex as possible wave , depending on the rtl engine's ram size. For EDA and Emulator, it is not a big issue.
For FPGA, it will cost resource, then need consider the cmd length; however, there still have a ping-pong buffer solution of FPGA,
to continuous generate wave stimulus.


## Architechture
The arch includes the 3 parts:
1. RTL engine
2. Python engine
3. User programming

### RTL engine
wgen.sv is the rtl engine, it read the cmd (I'd like to call it op) from internal sram. And parse it, do the initial op copy according the 
sequence and branch, copying the op to a smaller ring buffer. The execution code will read from the ring buffer, and parse it, then finally
do the operation.
The supported operation includes:
1. write output, direct or change on last write (+,-,<<,>>,nor)
2. read input, till input equal expected value
3. write then read
4. read then write
5. nop
6. repeat
   
The write or read operation, has a mask, to handle the selected bits. With the read(=wait or poll) cmd, the interface handshake is possilbe.
We can use it realize a valid/read handshake , most popular in axi/ahb/apb interface. Then can realize them all in a simple way, through cmd.
There is an example in later part.
The repeat cmd, can realize repeat operating some cmds as defined times, and support upto 4 level loop embeding.

### Python engine
wgen.py is the matching scripts, provide a friendly interface for user to coding cmd in readable format, not in binary. Example, we normally 
want to write "drive("wdata", "h1234")", not "1000001234", to drive an interface's wdata=0x1234.
wgen.py also provide the common tasks for calling, to match the rtl engines ability.
1. drive_t
2. wait_t
3. drv_wait_t
4. wait_drv_t
5. nop_t
6. repeat_t
   
There are several example to show how to call it later.
wgen.py also provide a config function, to simply define the generator's interface and ram depth. There will be a self-defined generator
(rtl module) with the config's interface.

### User programming
It is very simple to create a generator, and program the cmd code. Basically, it includes the 3 steps
1. Instance the python class wgen, and call config , with output/input interface and ram depth
2. Add behavior, by call the 6 tasks(drive_t, wait_t, drv_wait_t, wait_drv_t, nop_t, repeat_t)
3. Generate cmd files and rtl wrapper modules, and a testbench for quick sim. (default use VCS).
The wgen_demo.py, shows several examples.

## Examples
### basic_num
#### Step 1: config
    wgen = wg.Wgen("basic_num")
    wgen.pad_asm = 1
    # ----------- config gen in/out/param... -----------#
    wgen.config({
        "name": "basic_num",
        "output": {"num_1": 8,"num_1_en": 1, "num_2": 8, "num_2_en": 1},
        "ram_depth": 64,
        "ring_depth": 32
    })
#### Step 2: coding behavior
The below code, show 4 methods to generate 1 2 3 4. 
And finally show the code with num_1_en along with num_1.

    #to output num_1: 1->2->3->4, here are 4 methods, all works.
    # method-1
    wgen.drive_t("num_1", "1")
    wgen.drive_t("num_1", "2")
    wgen.drive_t("num_1", "3")
    wgen.drive_t("num_1", "4")
    wgen.nop_t()
    # method-2
    wgen.drive_t("num_1", "1")
    wgen.drive_t("num_1", "1", "ADD") #++
    wgen.drive_t("num_1", "1", "ADD") #++
    wgen.drive_t("num_1", "1", "ADD") #++
    wgen.nop_t()
    # method-3
    for i in range(4):
        wgen.drive_t("num_1", f'{i+1}')
    wgen.nop_t()
    # method-4
    wgen.drive_t("num_1", "1")
    loop0 = wgen.drive_t("num_1", "1", "ADD")
    wgen.repeat_t(3,loop0)
    wgen.nop_t()

    #output num_1 1->4 with num_1_en=1, others en=0
    wgen.drive_t("num_1, num_1_en", "1, 1")
    wgen.drive_t("num_1", "2")
    wgen.drive_t("num_1", "3")
    wgen.drive_t("num_1", "4")
    wgen.drive_t("num_1, num_1_en", "0, 0")
    
#### Step 3: generate files
    # ----------- output to file ------------#
    wgen.gen_op()
    wgen.gen_module()
    wgen.gen_module_tb()
    wgen.gen_makefile()

The wave as below:
![image](https://github.com/dvagent/wgen/assets/18358121/01592fe1-4b15-4406-88e4-f208763336cf)
Generated files:
* basic_num.sv
* basic_num_op.txt
* basic_num_ram.txt
* basic_num_tb.sv
* wgen.sv
* Makefile

Run sim with vcs: make all [tmo=100000]

### axi write handshake
### Step 1: config
Here shows part of axi write channel interface. Based on it, can write the full interface if need.

    wgen.config({
        "name": "axi_mst",
        "output": {"wvalid": 1,"awvalid": 1, "waddr": 32, "wdata": 32},
        "input": {"awready": 1, "wready": 1},
        "ram_depth": 64,
        "ring_depth": 32
    })
### Step 2: coding behavior
The below python code define the write handshake sequence in a plain way.
axi_write_fast2 is another shorter coding style, to reach the same target as axi_write.

    def axi_write(wgen, addr:str, wdata:str, wdelay:int=0):
        # ---------- operation start -----------#
        wgen.set_sigval("output", "h0")
        wgen.set_sigval("awvalid", "1")
        wgen.set_sigval("waddr", addr)
        wgen.drive_t("output")
        wgen.wait_drv_t("awready", "1", "awvalid", "0")
        wgen.set_sigval("wvalid", "1")
        wgen.set_sigval("wdata", wdata)
        if wdelay:
            wgen.nop_t(wdelay)
        wgen.drive_t("output")
        wgen.wait_drv_t("wready", "1", "wvalid", "0")
    
    def axi_write_fast2(wgen, addr:str, wdata:str):
        #no bubble of addr and wdata
        wgen.drive_t("waddr, awvalid", f"{addr}, 1")
        wgen.wait_drv_t("awready", "1", "wvalid, wdata, awvalid", f"1, {wdata}, 0")
        wgen.wait_drv_t("wready", "1", "wvalid", "0")

Later we can all the axi_write or axi_write_fast2 to simulate the axi write operation.

    axi_write(wgen, "h10", "h55555555")
    axi_write(wgen, "h14", "h66666666", 5)
    axi_write_fast(wgen, "h20", "h77777777")
    axi_write_fast(wgen, "h30", "h88888888")
    axi_write_fast2(wgen, "h40", "h99999999")
    axi_write_fast2(wgen, "h50", "haaaaaaaa")

The sim result as below:
![image](https://github.com/dvagent/wgen/assets/18358121/94875f5c-d749-41ed-9203-0565eceb6545)

## Summary
The wgen provide a programmable solution using python scripts to generate wave/stimulus, easily share the stimulus/masters between different
platform. And the python scripts is also a friendly way to programm, and easy to extend to powerful usage, eg, data source from file, from remote, 
from hw communication etc. 
The rtl engine is some like a "cycle cmd processor", and can enhace it with more cmd , such as jump etc. 
The limitation is that it more support fixed pattern, can't random like eda interface/master. But its synthesibility is most powerful.
In certain scenarios, shorten the tests porting effort, by sharing the same drivers.
