package main

import "core:fmt"
import "core:mem/virtual"
import "core:mem"
import "core:os"

import "backend"
import "frontend"


main :: proc() {
    string_arena: virtual.Arena
    _ = virtual.arena_init_growing(&string_arena)
    defer free_all(virtual.arena_allocator(&string_arena))

    sm := frontend.String_Manager{
        arena = &string_arena,
        allocations = make([dynamic]string, virtual.arena_allocator(&string_arena)),
    }

    filename := "./test/test.elk"    

    _ = compile_file(filename, &sm)
}


compile_file :: proc(filepath: string, sm: ^frontend.String_Manager) -> bool {
    //open the file
    data, ok := os.read_entire_file(filepath)
    if !ok {
        fmt.printf("Error: Unable to open file %s\n", filepath)
        return false
    }
    defer delete(data) //TODO could be deleted earlier 

    //prepare frontend
    file_arena: virtual.Arena
    _ = virtual.arena_init_growing(&file_arena)
    defer free_all(virtual.arena_allocator(&file_arena))

    file_allocator := virtual.arena_allocator(&file_arena)

    lexer := frontend.lexer_new(sm, data, filepath)
    parser, parser_ok := frontend.parser_new(&lexer, file_allocator)
    if !parser_ok do return false

    //after this call our parser is populated with the ast for the file
    frontend.parse(&parser) or_return

    //eventually imports here
    ir_context := backend.IR_Context{
        allocator = file_allocator,
        symbol_stack = backend.Symbol_Stack{
            sp = 0,
            allocator = file_allocator,
        }
    }

    ok = backend.context_create_file_ir(&ir_context, parser.file_level_statements[:])

    if !ok do panic("backend err")


    //global scope need not follow any logical order so we need to know what declarations to expect
    // ir_generator := backend.IR_Generator{
    //     allocator = file_allocator,
    //     user_defined_types = make([dynamic]backend.Type_Info, file_allocator),
    //     scopes = backend.Scope_Stack{
    //         sp = 0,
    //         allocator = file_allocator
    //     },
    //     program = make([dynamic]backend.Instruction, file_allocator)
    // }


    

    return true
}