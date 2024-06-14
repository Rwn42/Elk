package backend

import "core:strconv"

import fe"../frontend"

ctx_generate_expression :: proc(using ctx: ^IR_Context, node: fe.Elk_Expression, is_rvalue := true) -> (Register, Type_Info, bool) {
    #partial switch node_val in node {
        case ^fe.Elk_Binary_Expression: return ctx_generate_bin_op(ctx, node_val, is_rvalue)
        case fe.Elk_Number: return ctx_generate_number_literal(ctx, node_val)
        case fe.Elk_Identifier:
            symbol, found := scope_find(sm, node_val.data.?)
            if !found do elk_error("Unknown id %s", node_val.data.?)
            var_info, is_local := symbol.data.(Variable_Info)
            if !is_local do elk_error("symbol %s is not a local", node_val.data.?)
            reg := use_register(ctx)
            append(&program, Instruction{.Const, reg, var_info.stack_offset})
            if is_rvalue{
                append(&program, Instruction{.Load, reg, reg})
            }
            return reg, var_info.type_info, true
    }
    unreachable()
}

ctx_generate_bin_op :: proc(using ctx: ^IR_Context, node: ^fe.Elk_Binary_Expression, is_rvalue := true) -> (r: Register, t: Type_Info, b: bool) {
    is_rvalue := is_rvalue
    if node.operator.kind == .Equal do is_rvalue = false
    r1, info_l := ctx_generate_expression(ctx, node.lhs, is_rvalue) or_return
    r2, info_r := ctx_generate_expression(ctx, node.rhs, is_rvalue) or_return
    #partial switch node.operator.kind {
        case .Plus: append(&program, Instruction{.Add,r1,r2})
        case .Equal: append(&program, Instruction{.Store,r1,r2})
    }
    free_register(ctx)
    return r1, info_l, true
}


ctx_generate_number_literal :: proc(using ctx: ^IR_Context, node: fe.Elk_Number) -> (Register, Type_Info, bool) {
    reg := use_register(ctx)
    if integer, ok := strconv.parse_int(node.data.?); ok {
        append(&program, Instruction{
            opc = .Const,
            operand_a = reg,
            operand_b = integer,
        })
        return reg, Type_Info{size = WORD_SIZE,data = Type_Info_Untyped_Int{},}, true
    }

    if float, ok := strconv.parse_f64(node.data.?); ok {
        append(&program, Instruction{
            opc = .Const,
            operand_a = transmute(int)float,
        })
        return reg, Type_Info{size = WORD_SIZE,data = Type_Info_Real{},}, true
    }

    elk_error("Failed to parse number: %s", node)

    return 0, {}, false
}   