package backend

import "core:strconv"

import fe"../frontend"

ctx_generate_primary_expression :: proc(using ctx: ^IR_Context, node: fe.Elk_Expression, location: Expr_Result_Loc) -> (Type_Info, bool) {
    store_register :: proc(using ctx: ^IR_Context, location: Expr_Result_Loc, reg: Register) {
        switch location {
            case .None:
            case .Memory: append(&program, Instruction{.Store, reg, nil})
            case .Parameter: unimplemented("")
            case .Return: unimplemented("")
        }
    }

    #partial switch value in node {
        case ^fe.Elk_Assignment_Expression:
            l_info, reg, ok := ctx_generate_lvalue(ctx, value.lhs)
            append(&program, Instruction{.Mov, .Raddr, reg})
            if !ok do return {}, false
            return ctx_generate_primary_expression(ctx, value.rhs, .Memory)
        case ^fe.Elk_Array_Literal:
            result_info := Type_Info{}
            element_info := new(Type_Info) //TODO deal with mem leak
            for entry in value.entries{
                info, ok := ctx_generate_primary_expression(ctx, entry, location)
                append(&program, Instruction{.Add, .Raddr, info.size})
                result_info.size += info.size
                element_info^ = info
            }
            result_info.data = Type_Info_Array{length = len(value.entries), element_type = element_info}
            return result_info, true
        case fe.Elk_Identifier:
            symbol, ok := scope_find(sm, value.data.?)
            if !ok do return {}, false
            #partial switch type in symbol.data.(Variable_Info).type_info.data{
                case Type_Info_Array:
                    info, addr_reg, ok := ctx_generate_lvalue(ctx, node)
                    if !ok do return {}, false
                    for _ in 0..<type.length {
                        value_reg := ctx_use_register(ctx)
                        append(&program, Instruction{.Load, addr_reg, value_reg})
                        append(&program, Instruction{.Store, value_reg, nil})
                        append(&program, Instruction{.Add, addr_reg, type.element_type.size})
                        append(&program, Instruction{.Add, .Raddr, type.element_type.size})
                    }
                    return info, true
                case Type_Info_Struct:
                case Type_Info_Slice:
                case:
                    info, reg, ok := ctx_generate_simple_expression(ctx, node)
                    store_register(ctx, location, reg)
                    return info, ok
            }
        case: 
            info, reg, ok := ctx_generate_simple_expression(ctx, node)
            if !ok do return {}, false
            store_register(ctx, location, reg)
            return info, true
    }

    panic("Unreachable")
}

ctx_generate_simple_expression :: proc(using ctx: ^IR_Context, node: fe.Elk_Expression) -> (Type_Info, Register, bool) {
    #partial switch value in node {
        case fe.Elk_Number: return ctx_generate_number_literal(ctx, value)
        case fe.Elk_Bool: return ctx_generate_bool_literal(ctx, value)
        case fe.Elk_Identifier:
            info, addr_reg, ok := ctx_generate_lvalue(ctx, node)
            if !ok do return {}, .R1, false
            value_reg := ctx_use_register(ctx)
            append(&program, Instruction{.Load, addr_reg, value_reg})
            return info, value_reg, true
        case ^fe.Elk_Infix_Expression: return ctx_generate_infix(ctx, value)
        case: elk_error("Expected simple expression %v", value)
    }
    panic("Unreachable")
}

ctx_generate_infix :: proc(using ctx: ^IR_Context, node: ^fe.Elk_Infix_Expression) -> (info: Type_Info, reg: Register, ok: bool) {
    info_l, r1 := ctx_generate_simple_expression(ctx, node.lhs) or_return
    info_r, r2 := ctx_generate_simple_expression(ctx, node.rhs) or_return

    opc: Opcode
    #partial switch node.operator.kind {
        case .Plus: opc = .Add
        case .Asterisk: opc = .Mul
    }
    append(&program, Instruction{opc,r1, r2})

    return info_l, r1, true
}


ctx_generate_lvalue :: proc(using ctx: ^IR_Context, expr: fe.Elk_Expression) -> (Type_Info, Register, bool) {
    reg := ctx_use_register(ctx)
    #partial switch node_val in expr {
        case ^fe.Elk_Unary_Expression: unimplemented("unary")
        case fe.Elk_Identifier:
            symbol, found := scope_find(sm, node_val.data.?)
            if !found {
                elk_error("Unknown id %s", node_val.data.?)
                return {}, reg, false
            }
            var_info, is_local := symbol.data.(Variable_Info)
            if !is_local {
                elk_error("symbol %s is not a local", node_val.data.?)
                return {}, reg, false
            }
            append(&program, Instruction{.Const, reg, var_info.stack_offset})
            return var_info.type_info, reg, true
        case: elk_error("expr not an lvalue %s", expr)
    }
    return {}, reg, false
}


ctx_generate_number_literal :: proc(using ctx: ^IR_Context, node: fe.Elk_Number) -> (Type_Info, Register, bool) {
    if integer, ok := strconv.parse_int(node.data.?); ok {
        info := Type_Info{size = WORD_SIZE,data = Type_Info_Untyped_Int{},}
        result_register := ctx_use_register(ctx)
        append(&program, Instruction{opc = .Const, operand_a = result_register,operand_b = integer})
        return info, result_register, true
    }

    if float, ok := strconv.parse_f64(node.data.?); ok {
        info := Type_Info{size = WORD_SIZE,data = Type_Info_Real{}}
        result_register := ctx_use_register(ctx)
        append(&program, Instruction{opc = .Const, operand_a = result_register ,operand_b = transmute(int)float})
        return info, result_register, true
    }

    elk_error("Failed to parse number: %s", node)

    return {}, .R1, false
}

ctx_generate_bool_literal :: proc(using ctx: ^IR_Context, node: fe.Elk_Bool) -> (Type_Info, Register, bool) {
    reg := ctx_use_register(ctx)
    #partial switch node.kind{
        case .True: append(&program, Instruction{.Const, reg, 1})
        case .False: append(&program, Instruction{.Const, reg, 0})
        case: panic("Unreachable")
    }
    return Type_Info{size = 1, data = Type_Info_Bool{}}, reg, true
}

