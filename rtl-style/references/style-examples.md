# RTL风格示例

下面只约定写法。修改现有RTL时保留原有接口、信号名、编码和周期，不套入示例的功能。

## 分支体始终分行并加块

```systemverilog
always_comb begin
    if (select_primary) begin
        selected_data = primary_data;
    end else if (select_backup) begin
        selected_data = backup_data;
    end else begin
        selected_data = idle_data;
    end
end
```

这是已有三路选择逻辑的排版示例。本规范要求已有分支有`begin/end`，不要求凭空添加条件、分支或寄存器自赋值。

## 模块化端口声明与逐项例化

以下是接口片段，内部逻辑由真实设计提供。分组注释承载握手与时钟合同；同组端口仍然逐行声明。

```systemverilog
module result_sink #(
    parameter int DATA_WIDTH = 16  // 结果数据的位宽，单位为bit，合法值为正整数。
) (
    // 时钟／复位：全部接口属clk域；rst_n异步拉低，由外部同步释放。
    input  wire                  clk,
    input  wire                  rst_n,

    // 结果输入：valid与ready同为1的上升沿接收，反压期间保持data和valid。
    input  wire                  result_valid,
    output wire                  result_ready,
    input  wire [DATA_WIDTH-1:0]  result_data
);
```

```systemverilog
result_sink #(
    .DATA_WIDTH (RESULT_WIDTH)  // 透传父级结果位宽，保持接收端与返回数据的宽度一致。
) u_result_sink (
    // 时钟／复位：接收端使用控制域时钟，低有效复位由外部同步释放。
    .clk          (clk_ctrl),
    .rst_n        (ctrl_reset_n),

    // 结果输入及握手：valid与ready同高时接收，反压期间上游保持数据和valid。
    .result_valid (return_valid),
    .result_ready (return_ready),
    .result_data  (return_data)
);
```

标准单元和只有一个端口的实例也展开为相同形式；只有`std_dff*`和`std_ltch`原语例外，采用单行位置例化（见下文状态机示例和[primitives.md](primitives.md)第4.2节）。既有位置连接保持原顺序，一行一个连接；`.*`若原本存在，独占一行，不将命名连接批量替换为通配连接。

## 三段式状态机与逐状态、逐转移说明

这是一个完整的控制器风格示例：`start`只在空闲沿接受；`operation_done`最早在之后的等待周期出现。`S_REPORT`的一个报告周期属于本示例协议，不是所有设计都要增加的状态。没有超时需求，因此没有添加看门狗或锁定机制。状态寄存器由`std_dffr`原语实现，模块内参与综合的部分没有时序过程块；状态用枚举类型声明，仿真和Verdi中直接显示状态名。

```systemverilog
module request_controller (
    // 时钟／复位：接口在clk上升沿采样，低有效复位取消当前请求。
    input  wire   clk,
    input  wire   rst_n,

    // 请求／完成：start仅在busy=0时接受，operation_done由同域执行器返回。
    input  wire   start,
    input  wire   operation_done,
    output logic  busy,
    output logic  done
);

    typedef enum logic [1:0] {
        S_IDLE      = 2'd0,  // 等待新请求，允许上游在busy=0时发起操作；复位入口。
        S_WAIT_DONE = 2'd1,  // 请求已经接受，等待执行器完成；期间不接受新请求。
        S_REPORT    = 2'd2   // 对上游报告一拍done，保持busy直到报告周期结束。
    } state_t;

    state_t                    state_q;      // 当前状态，由state_raw_q显式转换得到。
    state_t                    state_d;      // 下一状态，由第二段组合逻辑给出。
    logic [$bits(state_t)-1:0] state_raw_q;  // 状态寄存器原语的logic输出，只用于转换为state_q。

    // 第一段：状态寄存器，复位进入S_IDLE以取消在途请求；复位释放后每拍装入下一状态。
    // 原语qout是logic向量，先接state_raw_q再显式转换，不直接连到枚举变量。
    std_dffr #(.DW($bits(state_t)), .RST_VAL(S_IDLE))
        u_state_dffr (state_d, state_raw_q, clk, rst_n);
    assign state_q = state_t'(state_raw_q);

    // 第二段：计算下一状态，不在本块更新计数、数据或输出。
    always_comb begin
        // 没有新请求或尚未完成时保持状态，不重复启动或提前报告。
        state_d = state_q;
        case (state_q)
            S_IDLE: begin
                if (start) begin
                    // 本沿接受请求，下一拍拉高busy并等待执行器完成。
                    state_d = S_WAIT_DONE;
                end
            end

            S_WAIT_DONE: begin
                if (operation_done) begin
                    // 捕获完成条件后进入报告周期，done在进入S_REPORT后有效。
                    state_d = S_REPORT;
                end
            end

            S_REPORT: begin
                // 报告只保持一拍，下一拍回空闲，允许后续请求。
                state_d = S_IDLE;
            end

            default: begin
                // 未使用的编码2'd3返回空闲入口，不产生完成脉冲。
                state_d = S_IDLE;
            end
        endcase
    end

    // 第三段：独立输出译码；默认值覆盖所有编码，组合逻辑不推断锁存器。
    always_comb begin
        busy = 1'b1;
        done = 1'b0;
        if (state_q == S_IDLE) begin
            busy = 1'b0;
        end
        if (state_q == S_REPORT) begin
            done = 1'b1;
        end
    end

    // synopsys translate_off
    // 仿真检查：执行器只应在等待完成期间返回operation_done，其他状态出现即报告错误。
    // 本块不参与综合，只读取设计信号，因此允许使用always_ff。
    always_ff @(posedge clk) begin
        if (rst_n && operation_done && (state_q != S_WAIT_DONE)) begin
            $error("request_controller: 状态%s收到意外的operation_done", state_q.name());
        end
    end
    // synopsys translate_on
endmodule
```

实际设计若有配置锁存、计数器、结果缓存或同步器，分别写出各自的`_set/_clr/_en/_d`逻辑和原语实例，说明更新使能、复位值和关键时序关系，不因为它们共用`clk/rst_n`就拼进状态寄存器实例。写法见[primitives.md](primitives.md)第4节。

对`state_d = success ? S_COMPLETE : S_RETRY;`一类既有代码，应在赋值前解释成功和失败各自的动作；对`case`后的强制错误跳转，应解释它会覆盖前面的正常转移。不要把默认恢复、错误锁定或成功优先级照抄到不具备这些行为的模块。

## 具名端口连接

端口内不写 `!event_tx_busy && !event_rx_busy && phy_idle_sync_q[1]` 等组合运算。
先定义具名组合信号，保持原时钟域、四态运算及零寄存延迟：

```systemverilog
logic event_idle;

// evt域：事件收发均排空且PHY管理接口空闲，才允许生命周期判断事件排空。
assign event_idle = !event_tx_busy && !event_rx_busy && phy_idle_sync_q[1];

dll_link_ctrl u_link (
    // evt域完整事件排空观察，不增加寄存周期。
    .event_idle_i (event_idle)
);
```

这里仅展示相关端口；实际实例须保留其他接口。输入拼接先具名再连接；输出拼接则先接完整具名信号，再用实例外的连续赋值拆分。直接信号、常量、位选择和部分选择可以保留；参数覆盖中的展开期常量计算可以保留。
