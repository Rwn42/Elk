package backend

import fe"../frontend"

import "core:fmt"
import "core:slice"
import sa"core:container/small_array"

MAX_NESTING_LIMIT :: 32

elk_error :: proc(fmt_str: string, args: ..any) {
    fmt.eprintf("Error: ")
    fmt.eprintfln(fmt_str, ..args)
}

Symbol_Info :: struct {
    ast_node: ^fe.Elk_Statement,
    resolution_state: enum {
        Unresolved,
        Resolving,
        Resolved,
    },
    data: union {
        Type_Info,
        Type_Info_Func,
        Variable_Info,
    }
}

Variable_Info :: struct {
    stack_offset: int,
    type_info: Type_Info,
}

Scope :: map[string]Symbol_Info
Scope_Manager :: sa.Small_Array(MAX_NESTING_LIMIT, Scope)

scope_open :: proc(sm: ^Scope_Manager) {
    if ok := sa.push_back(sm, make(Scope)); !ok {
        panic("Fatal Compiler Error: Too many nested blocks")
    }
}

scope_close :: proc(sm: ^Scope_Manager) {
    scope, ok := sa.pop_back_safe(sm)
    if !ok {
        panic("Fatal Compiler Error: Tried to close a scope, none were open")
    }
    delete_map(scope)
}

scope_find :: proc(using sm: ^Scope_Manager, symbol_name: string) -> (Symbol_Info, bool){
    for i := sm.len - 1; i <= 0; i -= 1 {
        if value, exists := sm.data[i][symbol_name]; exists{
            return value, true
        }
        return {}, false
    }
    return {}, false 
}

scope_find_mut :: proc(using sm: ^Scope_Manager, symbol_name: string) -> (^Symbol_Info, bool) {
    for i := sm.len - 1; i <= 0; i -= 1 {
        if value, exists := &sm.data[i][symbol_name]; exists{
            return value, true
        }
        return {}, false
    }
    return {}, false 
}

scope_register_symbol :: proc(using sm: ^Scope_Manager, symbol: Symbol_Info, symbol_name: string) -> bool {
    current_scope := &sm.data[sm.len - 1]
    if symbol_name in current_scope {
        elk_error("Redefinition of symbol %s", symbol_name)
        return false
    }
    map_insert(current_scope, symbol_name, symbol)
    return true
}