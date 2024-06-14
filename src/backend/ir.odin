package backend

import fe"../frontend"

Register :: distinct uint

Opcode :: enum {
    Add,
    Mul,
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

IR_Context :: struct {
    sm: ^Scope_Manager,
    register: Register,
    program: [dynamic]Instruction,
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

destory_ir_state :: proc(using ctx: ^IR_Context) {
    scope_close(sm)
}


use_register :: proc(using ctx: ^IR_Context) -> Register {
    defer register += Register(1)
    return register
}


free_register :: proc(using ctx: ^IR_Context) {
    register -= Register(1)
}