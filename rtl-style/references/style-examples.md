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

标准单元和只有一个端口的实例也展开为相同形式。既有位置连接保持原顺序，一行一个连接；`.*`若原本存在，独占一行，不将命名连接批量替换为通配连接。

## 三段式状态机与逐状态、逐转移说明

这是一个完整的控制器风格示例：`start`只在空闲沿接受；`operation_done`最早在之后的等待周期出现。`REPORT`的一个报告周期属于本示例协议，不是所有设计都要增加的状态。没有超时需求，因此没有添加看门狗或锁定机制。

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
        IDLE,       // 等待新请求，允许上游在busy=0时发起操作。
        WAIT_DONE,  // 请求已经接受，等待执行器完成；期间不接受新请求。
        REPORT      // 对上游报告一拍done，保持busy直到报告周期结束。
    } state_t;

    state_t state;
    state_t next_state;

    // 第一段：只更新状态寄存器，复位不产生完成报告。
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // 取消在途请求，恢复空闲接收入口。
            state <= IDLE;
        end else begin
            state <= next_state;
        end
    end

    // 第二段：计算下一状态，不在本块更新计数、数据或输出寄存器。
    always_comb begin
        // 没有新请求或尚未完成时保持状态，不重复启动或提前报告。
        next_state = state;
        case (state)
            IDLE: begin
                if (start) begin
                    // 本沿接受请求，下一拍拉高busy并等待执行器完成。
                    next_state = WAIT_DONE;
                end
            end

            WAIT_DONE: begin
                if (operation_done) begin
                    // 捕获完成条件后进入报告周期，done在进入REPORT后有效。
                    next_state = REPORT;
                end
            end

            REPORT: begin
                // 报告只保持一拍，下一拍回空闲，允许后续请求。
                next_state = IDLE;
            end

            default: begin
                // 未匹配的状态编码返回空闲入口，不产生完成脉冲。
                next_state = IDLE;
            end
        endcase
    end

    // 第三段：独立输出译码；默认值覆盖所有编码，组合逻辑不推断锁存器。
    always_comb begin
        busy = 1'b1;
        done = 1'b0;
        if (state == IDLE) begin
            busy = 1'b0;
        end
        if (state == REPORT) begin
            done = 1'b1;
        end
    end
endmodule
```

实际设计若有配置锁存、计数器、结果缓存或同步器，分别建立职责清晰的时序块。说明更新使能、复位值和关键时序关系，不因为它们共用`clk/rst_n`就并入状态寄存器块。

对`next_state = success ? COMPLETE : RETRY;`一类既有代码，应在赋值前解释成功和失败各自的动作；对`case`后的强制错误跳转，应解释它会覆盖前面的正常转移。不要把默认恢复、错误锁定或成功优先级照抄到不具备这些行为的模块。
