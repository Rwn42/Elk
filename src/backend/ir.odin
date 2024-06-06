package backend

import sa "core:container/small_array"
import "core:fmt"
import "core:slice"

import fe"../frontend"

MAXIMUM_NESTING_LIMIT :: 32 //why would anyone need more than 32 nested scopes?

Local_Info :: struct {
    info: Type_Info,
    stack_offset: int,
}

Symbol_Info :: struct {
    ast_node: fe.Elk_Statement,
    resolution_state: enum {
        Unresolved,
        Resolving,
        Resolved,
    },
    data: union {
        Type_Info,
        Type_Info_Func,
        Local_Info,
    }
}

Symbol_Table :: map[string]Symbol_Info

Opcode :: enum {
    Const,
    Add,
    Mul,
    Eq,
    Lt,
    Gt,
    Local_Store,
}

Entry_Idx :: distinct int
Operand :: union {
    i128, //if I decide to support 64 bit unsigned numbers I need the extra space
    Entry_Idx,
}

Instruction :: struct {
    opc: Opcode,
    l_operand: Operand,
    r_operand: Operand,
}


IR_Context :: struct {
    symbols: sa.Small_Array(MAXIMUM_NESTING_LIMIT, Symbol_Table),
    program: [dynamic]Instruction,
    current_local_offset: int,
}

ctx_create_global_context :: proc(using ctx: ^IR_Context, ast_roots: []fe.Elk_Statement) -> bool {
    ctx_register_builtins :: proc(using ctx: ^IR_Context) {
        integer_builtin := Symbol_Info{resolution_state = .Resolved, ast_node = nil, data = Type_Info{
            size = 8,
            data = Type_Info_Integer{},
        }}
        _ = ctx_register_symbol(ctx, integer_builtin, "int")

        real_builtin := Symbol_Info{resolution_state = .Resolved, ast_node = nil, data = Type_Info{
            size = 8,
            data = Type_Info_Real{},
        }}
        _ = ctx_register_symbol(ctx, real_builtin, "real")

        bool_builtin := Symbol_Info{resolution_state = .Resolved, ast_node = nil, data = Type_Info{
            size = 1,
            data = Type_Info_Bool{},
        }}
        _ = ctx_register_symbol(ctx, bool_builtin, "bool")

        byte_builtin := Symbol_Info{resolution_state = .Resolved, ast_node = nil, data = Type_Info{
            size = 1,
            data = Type_Info_Byte{},
        }}
        _ = ctx_register_symbol(ctx, bool_builtin, "byte")
        
        //needed for string builtin
        byte_symbol, _ := ctx_scope_find_mut(ctx, "byte")
        string_builtin := Symbol_Info{resolution_state = .Resolved, ast_node = nil, data = Type_Info{
            size = 16,
            data = Type_Info_Slice{
                element_type = &byte_symbol.data.(Type_Info)
            },
        }}
    }
    ctx_open_scope(ctx)

    ctx_register_builtins(ctx)

    for root in ast_roots {
        symbol := Symbol_Info {resolution_state = .Unresolved, ast_node = root, data = nil}
        ctx_register_symbol(ctx, symbol, fe.symbol_name(root)) or_return
    }

    for name, &symbol in symbols.data[symbols.len - 1] {
        if symbol.resolution_state == .Resolved do continue
        context_resolve_declaration(ctx, name) or_return
    }

    return true
}

ctx_open_scope :: proc(using ctx: ^IR_Context) {
    if ok := sa.push_back(&symbols, make(Symbol_Table)); !ok {
        panic("Fatal Compiler Error: Too many nested blocks")
    }
}

ctx_close_scope :: proc(using ctx: ^IR_Context) {
    scope, ok := sa.pop_back_safe(&ctx.symbols)
    if !ok {
        panic("Fatal Compiler Error: Tried to close a scope, none were open")
    }
    delete_map(scope)
}

ctx_scope_find :: proc(using ctx: IR_Context, symbol_name: string) -> (Symbol_Info, bool){
    for i := symbols.len - 1; i <= 0; i -= 1 {
        if value, exists := symbols.data[i][symbol_name]; exists{
            return value, true
        }
        return {}, false
    }
    return {}, false 
}

ctx_scope_find_mut :: proc(using ctx: ^IR_Context, symbol_name: string) -> (^Symbol_Info, bool) {
    for i := symbols.len - 1; i <= 0; i -= 1 {
        if value, exists := &symbols.data[i][symbol_name]; exists{
            return value, true
        }
        return {}, false
    }
    return {}, false 
}

ctx_register_symbol :: proc(using ctx: ^IR_Context, symbol: Symbol_Info, symbol_name: string) -> bool {
    current_scope := &symbols.data[symbols.len - 1]
    if symbol_name in current_scope {
        elk_error("Redefinition of symbol %s", symbol_name)
        return false
    }
    map_insert(current_scope, symbol_name, symbol)
    return true
}

context_resolve_declaration :: proc(using ctx: ^IR_Context, name: string) -> bool {
    resolve_function :: proc(using ctx: ^IR_Context, node: ^fe.Elk_Function_Declaration, sym: ^Symbol_Info) -> bool {
        param_name_builder := make([dynamic]string)
        param_type_builder := make([dynamic]^Type_Info)
        defer delete(param_name_builder)
        defer delete(param_type_builder)

        sym.resolution_state = .Resolving
        defer sym.resolution_state = .Resolved

        for field in node.params {
            field_type := context_get_type_info(ctx, field.type) or_return
            append(&param_name_builder, field.name.data.?)
            append(&param_type_builder, field_type)
        }

        func_info := Type_Info_Func{}
        func_info.parameter_names = slice.clone(param_name_builder[:])
        func_info.parameter_types = slice.clone(param_type_builder[:])
        if ret_type, ok := node.return_type.?; ok {
            func_info.return_type = context_get_type_info(ctx, ret_type) or_return
        }

        sym.data = func_info

        return true
    }
    resolve_struct :: proc(using ctx: ^IR_Context, node: ^fe.Elk_Struct_Declaration, sym: ^Symbol_Info) -> bool {
        field_name_builder := make([dynamic]string)
        field_type_builder := make([dynamic]^Type_Info)
        field_offset_builder := make([dynamic]int)
        defer delete(field_name_builder)
        defer delete(field_type_builder)
        defer delete(field_offset_builder)
        
        sym.resolution_state = .Resolving
        defer sym.resolution_state = .Resolved

        size: int = 0
        for field in node.fields {
            field_type := context_get_type_info(ctx, field.type) or_return
            append(&field_name_builder, field.name.data.?)
            append(&field_type_builder, field_type)
            append(&field_offset_builder, size) //todo padding
            size += field_type.size
        }

        sym.data = Type_Info{
            size = size,
            data = Type_Info_Struct{
                field_names = slice.clone(field_name_builder[:]),
                field_types = slice.clone(field_type_builder[:]),
                field_offsets = slice.clone(field_offset_builder[:]),
            }
        }
        return true
    }

    resolve_alias :: proc(using ctx: ^IR_Context, node: ^fe.Elk_Type_Alias, sym: ^Symbol_Info) -> bool {
        sym.resolution_state = .Resolving
        defer sym.resolution_state = .Resolved
        type := context_get_type_info(ctx, node.type) or_return
        sym.data = type^
        return true
    }

    resolve_decl :: proc{
        resolve_function,
        resolve_struct,
        resolve_alias,
    }

    declaration, found := ctx_scope_find_mut(ctx, name) 
    assert(found, "Attempt to resolve a declaration that was not in the scope stack")
    assert(declaration.resolution_state != .Resolved, "Attempt to re-resolve a declaration")
    
    #partial switch value in declaration.ast_node{
        case ^fe.Elk_Function_Declaration: resolve_decl(ctx, value, declaration)
        case ^fe.Elk_Struct_Declaration: resolve_decl(ctx, value, declaration)
        case ^fe.Elk_Type_Alias: resolve_decl(ctx, value, declaration)
        case: panic("Tried to resolve an unresovable declaration type")
    }
    return true
}

elk_error :: proc(fmt_str: string, args: ..any) {
    fmt.eprintf("Error: ")
    fmt.eprintfln(fmt_str, ..args)
}
