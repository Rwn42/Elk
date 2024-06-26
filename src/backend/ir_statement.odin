package backend

import fe"../frontend"

ctx_generate_stmt :: proc(using ctx: ^IR_Context, node: fe.Elk_Statement) -> bool {
    #partial switch stmt_val in node {
        case fe.Elk_Expression: 
            _, ok := ctx_generate_primary_expression(ctx, stmt_val, .None)
            return ok
        case ^fe.Elk_Variable_Declaration: return ctx_generate_var_decl(ctx, stmt_val^)
        case fe.Elk_Return:
        case: elk_error("Statement %s not allowed at function scope", node)
    
    }
    return false
}



ctx_generate_var_decl :: proc(using ctx: ^IR_Context, decl: fe.Elk_Variable_Declaration) -> bool {
    info: Variable_Info = {stack_offset = locals_size}
    defer locals_size += info.type_info.size

    ast_type, has_type := decl.type.?
    ast_expr, has_expr := decl.value.?
    name := decl.name.data.?

    if has_type{
        info.type_info = (get_type_info(sm, ast_type) or_return)^
        if !has_expr{
            scope_register_symbol(sm, Symbol_Info{data = info, resolution_state = .Resolved}, name) or_return
            return true
        }
    }else {
        if !has_expr{
            elk_error("Incomplete variable delcaration %s", decl)
            return false
        }
    }

    append(&program, Instruction{.Const, .Raddr, info.stack_offset})

    type_info := ctx_generate_primary_expression(ctx, ast_expr, .Memory) or_return

    info.type_info = type_info

    scope_register_symbol(sm, Symbol_Info{ast_node = nil, resolution_state = .Resolved, data = info}, name) or_return
    return true
}
