package backend

import fe"../frontend"

Register :: enum {
    R1,
    R2,
    R3,
    R4,
    Raddr,
    Rret,
}

Opcode :: enum {
    Add,
    Mul,
    Mov,
    Const,
    Ret,
    Load,
    Store,
}

Operand :: union {
    int,
    Register,
}

Instruction :: struct {
    opc: Opcode,
    operand_a: Operand,
    operand_b: Operand,
}

Expr_Result_Loc :: enum {
    None,
    Memory,
    Parameter,
    Return,
}

IR_Context :: struct {
    sm: ^Scope_Manager,
    temporary: Register,
    program: [dynamic]Instruction,
    static: [dynamic]byte,
    locals_size: int,
}

setup_ir_state :: proc(using ctx: ^IR_Context, ast_roots: []fe.Elk_Statement) -> bool {
    scope_open(sm)
    
    add_builtin_types_to_scope(sm)

    for root, idx in ast_roots {
        symbol := Symbol_Info {resolution_state = .Unresolved, ast_node = &ast_roots[idx], data = nil}
        scope_register_symbol(sm, symbol, fe.symbol_name(root)) or_return
    }

    for name, &symbol in sm.data[sm.len - 1] {
        if symbol.resolution_state == .Resolved do continue
        resolve_global_type(sm, name) or_return
    }

    return true
}

ctx_use_register :: proc(using ctx: ^IR_Context) -> Register {
    defer {
        if temporary == .R4 {
            temporary = .R1 
        }else{
            temporary = Register(int(temporary) + 1)
        }
    }
    return temporary
}

destory_ir_state :: proc(using ctx: ^IR_Context) {
    scope_close(sm)
}


