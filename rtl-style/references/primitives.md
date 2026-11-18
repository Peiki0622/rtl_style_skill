# std_／gnrl_原语库参考

本文件说明技能自带原语库的部署、目录、选型和例化写法。源码位于[`../assets/primitives/`](../assets/primitives/)，每个文件一个模块，均按本技能风格编写。

- `std_`：单元级原语，如触发器、锁存器、门控时钟、时钟选择、同步器和复位同步器。时序`always`只允许出现在`std_`原语和`gnrl_ram_*`存储模型内部。
- `gnrl_`：由`std_`原语搭成的通用功能块，如流水级、FIFO、跨时钟域握手、异步FIFO、仲裁器和存储器模型。

## 1. 部署到项目

1. 先搜索项目是否已有等价原语库（例如`sirv_gnrl_dff*`、公司`*_dff*`库）。已有时沿用项目库，不复制本库造成同功能双份；同一模块内不混用两套库。项目库缺少的功能再按本库同样的约定补充。
2. 项目没有原语库时，把`assets/primitives/`整个目录复制到项目的公共RTL目录（例如`rtl/common/primitives/`），保留`std/`、`gnrl/`子目录和`std_defines.svh`。不要在被复制的原语中加入项目功能；需要新原语时按同样的约定新增文件。
3. 仿真使用`primitives.f`：先设置`STD_PRIM_ROOT`为原语目录，再`-f $STD_PRIM_ROOT/primitives.f`。原语文件不写`` `timescale ``，须用编译选项统一指定（如VCS的`-timescale=1ns/1ps`），否则与带`` `timescale ``的测试平台混编会报错；`STD_SIM_DELAY`的`#1`为一个时间单位，最短时钟周期须大于它。综合工具不读取`.f`时按同一顺序加入源文件，并把原语目录加入头文件搜索路径（所有文件都`include "std_defines.svh"`）。
4. 按流程设置宏：

| 宏 | 何时定义 | 作用 |
|---|---|---|
| `STD_SIM_DELAY` | 只在RTL仿真需要区分采样沿前后的波形时 | 原语寄存器赋值展开为`<= #1`；综合、形式验证和门级流程禁止定义 |
| `STD_FPGA_SOURCE` | FPGA流程 | `std_clkgate`直通时钟；X检查断言不编译 |
| `STD_DISABLE_ASSERTION` | 仿真器不支持SVA或门级仿真 | 关闭原语内置X检查 |

X检查在仿真第0个时钟沿就开始生效，不受复位屏蔽；测试平台必须在第一个时钟沿前把输入驱动为确定值。

5. ASIC流程中，`std_clkgate`、`std_clk_mux2`、`gnrl_ram_sp`和`gnrl_ram_tp`是工艺单元或存储宏的唯一替换点：保持端口和读延迟，把模块体替换为工艺ICG、时钟MUX或编译器生成的存储宏，并按项目要求设置`dont_touch`。功能模块不直接例化工艺单元。

## 2. 原语目录

### 2.1 寄存器与锁存器（端口顺序固定，可单行位置例化）

| 原语 | 固定端口顺序 | 参数 | 行为 | 典型用途 |
|---|---|---|---|---|
| `std_dff` | `(dnxt, qout, clk)` | `DW` | 每拍装入，无复位 | 由valid限定的每拍更新数据级 |
| `std_dffr` | `(dnxt, qout, clk, rst_n)` | `DW`、`RST_VAL` | 每拍装入，异步复位为`RST_VAL` | 同步器级、边沿检测、每拍更新的控制信号 |
| `std_dffrs` | `(dnxt, qout, clk, rst_n)` | `DW` | 每拍装入，异步复位为全1 | 复位为全1的每拍更新信号 |
| `std_dffl` | `(lden, dnxt, qout, clk)` | `DW` | `lden`为1装入，无复位 | FIFO存储体、数据缓存、小寄存器堆 |
| `std_dfflr` | `(lden, dnxt, qout, clk, rst_n)` | `DW`、`RST_VAL` | `lden`为1装入，异步复位为`RST_VAL` | 有效标志、状态、计数器、指针、配置寄存器 |
| `std_dfflrs` | `(lden, dnxt, qout, clk, rst_n)` | `DW` | `lden`为1装入，异步复位为全1 | 复位为全1的保持型寄存器 |
| `std_ltch` | `(lden, dnxt, qout)` | `DW` | 高电平透明锁存 | 仅限经评审确认的锁存器场合 |

所有带`lden`的原语在仿真中检查`lden`不为X/Z，出现即`$fatal`。`RST_VAL`位宽等于`DW`，默认全0。

### 2.2 时钟、复位与同步（按名称逐行例化）

| 原语 | 端口 | 参数 | 要点 |
|---|---|---|---|
| `std_clkgate` | `clk_in`、`test_mode`、`clock_en`、`clk_out` | — | 低电平锁存使能的ICG；`test_mode`强制开时钟；FPGA直通，因此门控只能用于省功耗 |
| `std_clk_mux2` | `clk0`、`clk1`、`sel`、`clk_out` | — | 静态时钟选择，不做无毛刺切换 |
| `std_sync` | `din_a`、`dout`、`clk`、`rst_n` | `DP`≥2、`DW`、`RST_VAL` | 电平同步，延迟`DP`到`DP+1`拍；`DW>1`只用于格雷码等每次最多一位变化的信号 |
| `std_rst_sync` | `clk`、`rst_n_a`、`test_mode`、`rst_n_sync` | `DP`≥2 | 异步置位、同步释放；释放后第`DP`个上升沿输出1；测试模式旁路 |
| `std_pulse_sync` | `src_clk`、`src_rst_n`、`src_pulse`、`dst_clk`、`dst_rst_n`、`dst_pulse` | `SYNC_DP` | 翻转式脉冲同步，无背压；相邻源脉冲至少间隔两个目标周期 |

### 2.3 通用功能块（按名称逐行例化）

| 原语 | 参数 | 时序要点 |
|---|---|---|
| `gnrl_pipe_stage` | `CUT_READY`、`DP`（0或1）、`DW` | `DP=1`插入一级寄存器；`CUT_READY=1`切断`o_rdy`到`i_rdy`的组合路径，吞吐率每两拍一笔 |
| `gnrl_fifo` | `CUT_READY`、`MSKO`、`DP`、`DW` | 同步FIFO，独热指针、温度计占用量；无同拍旁路；`DP>1`时满即不收；`MSKO=1`空时输出0 |
| `gnrl_bypbuf` | `DP`（≥1）、`DW` | FIFO为空且下游就绪时同拍旁路；`i_rdy`只看FIFO是否满，切断ready路径而不增加空载延迟 |
| `gnrl_cdc_tx` | `DW`、`SYNC_DP` | 本域valid/ready转四相握手；`o_vld`、`o_dat`来自寄存器 |
| `gnrl_cdc_rx` | `DW`、`SYNC_DP` | 四相握手转本域valid/ready；与`gnrl_cdc_tx`配对使用 |
| `gnrl_async_fifo` | `DP`（2的幂且≥2）、`DW`、`SYNC_DP` | 格雷码指针异步FIFO；空满判断保守；两侧复位同时有效 |
| `gnrl_rr_arb` | `N` | 组合独热授权；`gnt_ack`为1时轮转优先级；复位后第0路优先 |
| `gnrl_ram_sp` | `DP`、`DW`、`MW` | 单端口同步RAM模型，读延迟1拍，读数据保持到下一次读 |
| `gnrl_ram_tp` | `DP`、`DW`、`MW` | 一写一读同步RAM模型；同拍读写同址时模型读旧值，设计不得依赖 |

## 3. 选型

1. **控制寄存器**（有效标志、状态、计数器、指针、配置、握手应答）必须复位：需要保持时用`std_dfflr`，每拍更新时用`std_dffr`；复位值非0时设置`RST_VAL`，全1可用`std_dfflrs`／`std_dffrs`。
2. **数据寄存器**只有在下游始终以有效标志限定使用时才可以不复位：保持型用`std_dffl`，每拍更新用`std_dff`；在注释中写明由哪个有效标志限定。数据会直接驱动控制、地址或对外接口时使用带复位版本。
3. **跨时钟域**：单比特电平用`std_sync`；单周期事件用`std_pulse_sync`；低速多比特数据用`gnrl_cdc_tx`＋`gnrl_cdc_rx`；连续数据流用`gnrl_async_fifo`。不得手写同步链或直接采样其他时钟域的多比特数据。
4. **复位**：每个时钟域通过各自的`std_rst_sync`得到本域复位，不把外部异步复位直接接到触发器。
5. **时钟**：门控只用`std_clkgate`，静态时钟选择只用`std_clk_mux2`；不在功能模块里写`assign clk_x = clk & en`或时钟三目选择。
6. **缓冲**：需要打一拍时用`gnrl_pipe_stage`；ready路径是关键路径时使用`CUT_READY=1`或`gnrl_bypbuf`；需要多条缓冲用`gnrl_fifo`。
7. **存储**：几十个条目以内的寄存器堆用`generate`循环例化`std_dffl`；更大的存储使用`gnrl_ram_sp`或`gnrl_ram_tp`，由后端替换为存储宏。

## 4. 例化写法

### 4.1 命名

| 后缀 | 含义 |
|---|---|
| `xxx_r` | 原语`qout`，寄存器当前值 |
| `xxx_nxt` | 原语`dnxt`，下一值 |
| `xxx_ena` | 原语`lden`，更新使能 |
| `xxx_set`／`xxx_clr` | 置位、清零条件，由它们组合出`_ena`和`_nxt` |

实例命名为`u_<寄存器名>_<原语简称>`，例如`u_vld_dfflr`、`u_state_dffr`、`u_fifo_rf_dffl`。

### 4.2 单行位置例化（只适用于`std_dff*`和`std_ltch`）

- 一个实例一行，端口按2.1节固定顺序位置连接；参数一律按名称覆盖，`RST_VAL`取默认值时可以省略。
- 位置连接同样不得直接写逻辑表达式：`dnxt`、`lden`等先用具名的`_nxt`、`_ena`信号计算再连接；直接信号、位／部分选择和常量可以保留。
- 实例上方紧邻一行中文注释，说明寄存器用途、复位值依据和更新条件；它代替逐项参数行尾注释。同功能的一组寄存器可共用一段注释，但每个寄存器的复位和更新条件都要写清楚。
- 单行超过100列时，可在参数列表后换行；端口连接仍然保持在同一行，顺序不变。
- 其他`std_`和全部`gnrl_`实例按名称逐行连接，遵守端口分组注释和参数行尾注释要求。

### 4.3 set/clr标志

```systemverilog
// 输出有效标志：复位为0；输入握手置位、输出握手清零，同拍发生时置位优先，保持有效。
assign vld_set = i_vld & i_rdy;
assign vld_clr = o_vld & o_rdy;
assign vld_ena = vld_set | vld_clr;
assign vld_nxt = vld_set | (~vld_clr);
std_dfflr #(.DW(1)) u_vld_dfflr (vld_ena, vld_nxt, vld_r, clk, rst_n);
```

清零优先时写`vld_nxt = vld_set & (~vld_clr)`，并在注释中说明原因。

### 4.4 计数器与配置寄存器

```systemverilog
// 超时计数：复位为0；start时清零重新计数，busy期间每拍加1，其余时间保持。
assign tmo_cnt_ena = start | busy_r;
assign tmo_cnt_nxt = start ? '0 : (tmo_cnt_r + 1'b1);
std_dfflr #(.DW(CNT_W)) u_tmo_cnt_dfflr (tmo_cnt_ena, tmo_cnt_nxt, tmo_cnt_r, clk, rst_n);

// 分频配置：复位为CFG_DIV_DEFAULT，使上电后无需软件配置即可工作；cfg_wr时写入。
std_dfflr #(.DW(8), .RST_VAL(CFG_DIV_DEFAULT))
    u_cfg_div_dfflr (cfg_wr, cfg_wdata[7:0], cfg_div_r, clk, rst_n);
```

### 4.5 数据级与小寄存器堆

```systemverilog
// 结果数据：只在结果握手时装入；不复位，下游以res_vld_r限定使用。
std_dffl #(.DW(DW)) u_res_dat_dffl (res_set, res_dat_nxt, res_dat_r, clk);

// 寄存器堆：每个条目在写使能且地址匹配时装入；不复位，读出由软件保证先写后读。
for (genvar i = 0; i < RF_DP; i = i + 1) begin : g_rf
    assign rf_wen[i] = wr_en & (wr_addr == RF_AW'(i));
    std_dffl #(.DW(DW)) u_rf_dffl (rf_wen[i], wr_dat, rf_r[i], clk);
end
```

### 4.6 状态寄存器（三段式第一段）

```systemverilog
localparam logic [1:0] IDLE      = 2'd0;  // 等待新请求，允许上游在busy=0时发起操作。
localparam logic [1:0] WAIT_DONE = 2'd1;  // 请求已接受，等待执行器完成；期间不接受新请求。
localparam logic [1:0] REPORT    = 2'd2;  // 对上游报告一拍done，下一拍回到IDLE。

logic [1:0] state_r;    // 当前状态。
logic [1:0] state_nxt;  // 下一状态，由第二段组合逻辑给出。

// 第一段：状态寄存器，复位进入IDLE，每拍装入第二段计算的下一状态。
std_dffr #(.DW(2), .RST_VAL(IDLE)) u_state_dffr (state_nxt, state_r, clk, rst_n);
```

状态编码用`localparam`；使用`enum`时须先在`logic`向量上例化原语，再显式转换为枚举类型。不能直接把`logic`输出口连到枚举变量。

### 4.7 跨时钟域

```systemverilog
// 启动请求同步：cfg域的start_lvl_r是寄存器输出，同步到core域后使用；复位值与源端一致为0。
std_sync #(
    .DP      (2),     // 两级同步，满足本设计频率下的MTBF要求。
    .DW      (1),     // 单比特电平。
    .RST_VAL (1'b0)   // 与源端寄存器复位值一致，复位释放后不产生假启动。
) u_start_sync (
    // 异步输入：cfg域寄存器输出，无组合逻辑。
    .din_a (start_lvl_r),

    // 同步输出：core域电平。
    .dout  (start_lvl_sync),

    // 时钟／复位：core域。
    .clk   (core_clk),
    .rst_n (core_rst_n)
);
```

## 5. 范围与限制

- 本库不包含无毛刺动态时钟切换、带几乎满／几乎空水位的FIFO、带ECC的存储器和多读口寄存器堆；需要时按本库约定新增并验证。
- 时钟门控、时钟选择和RAM模块是行为模型，ASIC流程须替换为工艺单元，替换后重新做等价性或门级验证。
- 原语自检（VCS仿真、DC展开、变异检查）脚本位于技能仓库的`verification/primitives/`目录，不随技能安装；项目中使用原语后仍须按项目流程验证设计本身。
