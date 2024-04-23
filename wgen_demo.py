import wgen as wg
def basic_num_cfg():
    wgen = wg.Wgen("basic_num")
    wgen.pad_asm = 1
    # ----------- config gen in/out/param... -----------#
    wgen.config({
        "name": "basic_num",
        "output": {"num_1": 8,"num_1_en": 1, "num_2": 8, "num_2_en": 1},
        "ram_depth": 64,
        "ring_depth": 32
    })
    print(wgen.cfg)
    return wgen

def basic_num_run1(wgen):
    #to output num_1: 1->2->3->4, here are 4 methods, all works.
    # method-1
    wgen.drive_t("num_1", "1")
    wgen.drive_t("num_1", "2")
    wgen.drive_t("num_1", "3")
    wgen.drive_t("num_1", "4")
    wgen.nop_t()
    # method-2
    wgen.drive_t("num_1", "1")
    wgen.drive_t("num_1", "1", "ADD")
    wgen.drive_t("num_1", "1", "ADD")
    wgen.drive_t("num_1", "1", "ADD")
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


def basic_num_run2(wgen, n1=16, n2=16):
    #2 level loop
    wgen.drive_t("output","0")
    wgen.drive_t("num_1_en,num_2_en", "1, 1")
    loop0 = wgen.drive_t("num_1", "1", "ADD")
    wgen.drive_t("num_1", "1", "ADD")
    wgen.drive_t("num_1", "1", "ADD")
    wgen.drive_t("num_1", "1", "ADD")
    wgen.repeat_t(n1//4, loop0)
    wgen.drive_t("num_1", "0", )
    wgen.drive_t("num_2", "1", "ADD")
    wgen.repeat_t(n2 , loop0)
    wgen.drive_t("num_1_en,num_2_en", "0, 0")

def axi_mst_cfg():
    wgen = wg.Wgen("mywgen")
    wgen.pad_asm = 1
    # ----------- config gen in/out/param... -----------#
    wgen.config({
        "name": "axi_mst",
        "output": {"wvalid": 1,"awvalid": 1, "waddr": 32, "wdata": 32},
        "input": {"awready": 1, "wready": 1},
        "ram_depth": 64,
        "ring_depth": 32
    })
    print(wgen.cfg)
    return wgen

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

def axi_write_fast(wgen, addr:str, wdata:str):
    #no bubble of addr and wdata
    wgen.set_sigval("awvalid", "1")
    wgen.set_sigval("waddr", addr)
    wgen.drive_t("output")
    wgen.set_sigval("wvalid", "1")
    wgen.set_sigval("wdata", wdata)
    wgen.set_sigval("awvalid", "0")
    wgen.wait_drv_t("awready", "1", "output")
    wgen.wait_drv_t("wready", "1", "wvalid", "0")

def axi_write_fast2(wgen, addr:str, wdata:str):
    #no bubble of addr and wdata
    wgen.drive_t("waddr, awvalid", f"{addr}, 1")
    wgen.wait_drv_t("awready", "1", "wvalid, wdata, awvalid", f"1, {wdata}, 0")
    wgen.wait_drv_t("wready", "1", "wvalid", "0")

def axi_slv_cfg():
    wgen = wg.Wgen("mywgen")
    #----------- config gen in/out/param... -----------#
    wgen.config({
        "name": "axi_slv",
        "input": {"wvalid": 1,"awvalid": 1, "waddr": 32, "wdata": 32},
        "output": {"awready": 1, "wready": 1},
        "ram_depth": 64,
        "ring_depth": 32
    })
    print(wgen.cfg)
    return wgen

def axi_slv_ack(wgen):
    #---------- operation start -----------#
    wgen.drive_t("awready, wready","0,0")
    wgen.wait_t("awvalid", "h1")
    wgen.drive_t("awready", "h1")
    wgen.wait_t("wvalid", "h1")
    wgen.drive_t("wready", "h1")

def ipi_mst_cfg():
    wgen = wg.Wgen("mywgen")
    #----------- config gen in/out/param... -----------#
    wgen.config({
        "name": "ipi_mst",
        "output": {"vsync":     1,
                   "hsync":     1,
                   "pixen":     1,
                   "odd_line":  1,
                   "pixdata":   16,
                   "end_frame": 1,
                   "embedded":  1,
                   "end_line":  1,
                   "data_begin":1,
                   "data_end":  1,
                   "data_valid":3,
                   "crc_line_err":1,
                   "parity":    4},
        "input": {"halt": 1},
        "ram_depth": 256,
        "ring_depth": 64
    })
    print(wgen.cfg)
    return wgen

def ipi_frame(wgen, hsize=200, wsize=100, frame_num=1, h2w_dly=0, w2h_dly=0, f2f_dly=0):
    #vsync: __|
    #hsync: __|
    loop_2_s = wgen.drive_t("vsync, hsync", "1, 1")
    #vsync: __|^|__
    #hsync: __|^|__
    wgen.drive_t("vsync, hsync", "0, 0")
    if h2w_dly:
        wgen.nop_t(h2w_dly)
    #pixen: ____|^^^^^^^^^^^^^^^|_______
    #pdata: ~~~~<===============>~~~~~~
    wgen.drive_t("pixdata, pixen", "1, 1")
    loop_0_s = wgen.drive_t("pixdata", "1", "ADD") #++
    wgen.drive_t("pixdata", "1", "ADD")  # ++
    wgen.drive_t("pixdata", "1", "ADD")  # ++
    wgen.drive_t("pixdata", "1", "ADD")  # ++
    wgen.repeat_t((wsize-1)//4, loop_0_s) # avoid cmd buf underflow
    if (wsize-1)%4:
        for i in range((wsize-1)%4):
            wgen.drive_t("pixdata", "1", "ADD")  # ++
    wgen.drive_t("pixdata, pixen", "0, 0")
    if w2h_dly:
        wgen.nop_t(w2h_dly)
    #vsync: ________
    #hsync: _______|
    loop_1_s = wgen.drive_t("hsync", "1")
    wgen.drive_t("hsync", "0")
    #vsync: ___________________
    #hsync: _______|^|_________
    if h2w_dly:
        wgen.nop_t(h2w_dly)
    #____|^^^^^^^^^^^^^^^|_______
    #~~~~<===============>~~~~~~
    wgen.drive_t("pixdata, pixen", "1, 1")
    loop_0_s = wgen.drive_t("pixdata","1","ADD") #++
    wgen.drive_t("pixdata", "1", "ADD")  # ++
    wgen.drive_t("pixdata", "1", "ADD")  # ++
    wgen.drive_t("pixdata", "1", "ADD")  # ++
    wgen.repeat_t((wsize-1)//4, loop_0_s) # avoid cmd buf underflow
    if (wsize-1)%4:
        for i in range((wsize-1)%4):
            wgen.drive_t("pixdata", "1", "ADD")  # ++
    wgen.drive_t("pixdata, pixen", "0, 0")
    if w2h_dly:
        wgen.nop_t(w2h_dly)
    wgen.repeat_t((hsize - 1), loop_1_s)
    if f2f_dly:
        wgen.nop_t(f2f_dly)
    wgen.repeat_t(frame_num, loop_2_s)

def gen(wgen):
    # ----------- output to file ------------#
    wgen.gen_op()
    wgen.gen_module()
    wgen.gen_module_tb()
    wgen.gen_makefile()

if __name__ == "__main__":
    #-- basic num --#
    wgen = basic_num_cfg()
    basic_num_run1(wgen)
    basic_num_run2(wgen)
    gen(wgen)
    
    #-- axi mst --#
    wgen = axi_mst_cfg()
    axi_write(wgen, "h10", "h55555555")
    axi_write(wgen, "h14", "h66666666", 5)
    axi_write_fast(wgen, "h20", "h77777777")
    axi_write_fast(wgen, "h30", "h88888888")
    axi_write_fast2(wgen, "h40", "h99999999")
    axi_write_fast2(wgen, "h50", "haaaaaaaa")
    gen(wgen)

    #-- axi slv --#
    wgen = axi_slv_cfg()
    axi_slv_ack(wgen)
    gen(wgen)

    #-- ipi mst --#
    wgen = ipi_mst_cfg()
    ipi_frame(wgen, 20, 40, 10)
    wgen.nop_t(100)
    ipi_frame(wgen, 200, 400, 8)
    #try the maxium size frame
    # wgen.nop_t(100)
    # ipi_frame(wgen,4000,3000,4)
    gen(wgen)