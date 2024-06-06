package backend

import "base:runtime"
import "core:fmt"

import fe"../frontend"

WORD_SIZE :: 8

Type_Info :: struct {
    size: int,
    data: union {
        Type_Info_Pointer,
        Type_Info_Integer,
        Type_Info_Bool,
        Type_Info_Byte,
        Type_Info_Real,
        Type_Info_Array,
        Type_Info_Slice,
        Type_Info_Func,
        Type_Info_Struct,
    }
}


Type_Info_Integer :: struct {}
Type_Info_Real :: struct  {}
Type_Info_Bool :: struct {}
Type_Info_Byte :: struct {}
Type_Info_Array :: struct {element_type: ^Type_Info}
Type_Info_Slice :: struct {element_type: ^Type_Info}
Type_Info_Pointer :: struct {element_type: ^Type_Info}
Type_Info_Func :: struct {
    parameter_names: []string,
    parameter_types: []^Type_Info,
    return_type: ^Type_Info,
}
Type_Info_Struct :: struct {
    field_names: []string,
    field_types: []^Type_Info,
    field_offsets: []int,
}


context_get_type_info :: proc(using ctx: ^IR_Context, node: fe.Elk_Type_Node) -> (info: ^Type_Info, ok: bool) {
    switch value in node {
        case ^fe.Elk_Pointer_Type:
            info := new(Type_Info)
            info.data = Type_Info_Pointer{element_type = context_get_type_info(ctx, value.pointing_to) or_return}
            info.size = WORD_SIZE
        case fe.Elk_Basic_Type:
            name := value.data.(string)
            symbol := ctx_scope_find_mut(ctx, name) or_return
            switch symbol.resolution_state{
                case .Unresolved:
                    context_resolve_declaration(ctx, name) or_return
                    symbol = ctx_scope_find_mut(ctx, name) or_return
                case .Resolving:
                    elk_error("Recursive Data Definition of Symbol %s", name)
                    return {}, false
                case .Resolved:
            }
            type_info, is_type := &symbol.data.(Type_Info)
            if !is_type{
                elk_error("Symbol %s is not a type", name)
                return {}, false
            }
            return type_info, true
    }
    unreachable()
}

