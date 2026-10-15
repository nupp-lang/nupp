define internal i32 @nupp.wrap.u32(double %v) #2 {
  %shifted = fadd double %v, 0x4338000000000000
  %bits = bitcast double %shifted to i64
  %out = trunc i64 %bits to i32
  ret i32 %out
}
@ks.rt = internal global ptr null
declare i32 @lua_checkstack(ptr, i32)
declare ptr @luaL_checklstring(ptr, i32, ptr)
@nupp.bytes.1 = private unnamed_addr constant [65 x i8] c"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/\00", align 4
@nupp.bytes.2 = private unnamed_addr constant [257 x i8] c"\FF\FF\FF\FF\FF\FF\FF\FF\FF\FF\FF\FF\FF\FF\FF\FF\FF\FF\FF\FF\FF\FF\FF\FF\FF\FF\FF\FF\FF\FF\FF\FF\FF\FF\FF\FF\FF\FF\FF\FF\FF\FF\FF>\FF\FF\FF?456789:;<=\FF\FF\FF\FF\FF\FF\FF\00\01\02\03\04\05\06\07\08\09\0A\0B\0C\0D\0E\0F\10\11\12\13\14\15\16\17\18\19\FF\FF\FF\FF\FF\FF\1A\1B\1C\1D\1E\1F !\22#$%&'()*+,-./0123\FF\FF\FF\FF\FF\FF\FF\FF\FF\FF\FF\FF\FF\FF\FF\FF\FF\FF\FF\FF\FF\FF\FF\FF\FF\FF\FF\FF\FF\FF\FF\FF\FF\FF\FF\FF\FF\FF\FF\FF\FF\FF\FF\FF\FF\FF\FF\FF\FF\FF\FF\FF\FF\FF\FF\FF\FF\FF\FF\FF\FF\FF\FF\FF\FF\FF\FF\FF\FF\FF\FF\FF\FF\FF\FF\FF\FF\FF\FF\FF\FF\FF\FF\FF\FF\FF\FF\FF\FF\FF\FF\FF\FF\FF\FF\FF\FF\FF\FF\FF\FF\FF\FF\FF\FF\FF\FF\FF\FF\FF\FF\FF\FF\FF\FF\FF\FF\FF\FF\FF\FF\FF\FF\FF\FF\FF\FF\FF\FF\FF\FF\FF\FF\00", align 4
@nupp.bytes.3 = private unnamed_addr constant [3 x i8] c"%s\00", align 1
@nupp.bytes.4 = private unnamed_addr constant [32 x i8] c"AOT builder Lua stack exhausted\00", align 1
declare i32 @luaL_error(ptr, ptr, ...)
declare i32 @lua_type(ptr, i32)
declare void @lua_pushnil(ptr)
declare void @lua_pushvalue(ptr, i32)
@nupp.bytes.5 = private unnamed_addr constant [8 x i8] c"require\00", align 1
declare void @lua_getfield(ptr, i32, ptr)
@nupp.bytes.6 = private unnamed_addr constant [19 x i8] c"nupp.runtime.native", align 1
declare void @lua_pushlstring(ptr, ptr, i64)
declare void @lua_call(ptr, i32, i32)
@nupp.bytes.7 = private unnamed_addr constant [11 x i8] c"aotRuntime\00", align 1
declare ptr @lua_tolstring(ptr, i32, ptr)
@nupp.bytes.8 = private unnamed_addr constant [56 x i8] c"AOT runtime is not the one this module was compiled for\00", align 1
declare void @lua_settop(ptr, i32)
declare void @lua_createtable(ptr, i32, i32)
@nupp.bytes.9 = private unnamed_addr constant [9 x i8] c"encodeAot", align 1
declare void @lua_pushcclosure(ptr, ptr, i32)
declare void @lua_rawset(ptr, i32)
@nupp.bytes.10 = private unnamed_addr constant [9 x i8] c"decodeAot", align 1

define internal i32 @ks_encode_aot_helper_u32(double %h_a_value) #1 {
entry:
  br label %body
body:
  %t1 = call i32 @nupp.wrap.u32(double %h_a_value)
  ret i32 %t1
}

define internal i32 @ks_encode_aot_helper_shr(i32 %h_a_value, i32 %h_a_count) #1 {
entry:
  br label %body
body:
  %t1 = and i32 %h_a_count, 31
  %t2 = lshr i32 %h_a_value, %t1
  ret i32 %t2
}

define internal i32 @ks_encode_aot_helper_add(i32 %h_a_a, i32 %h_a_b) #1 {
entry:
  br label %body
body:
  %t1 = add i32 %h_a_a, %h_a_b
  ret i32 %t1
}

define internal i32 @ks_encode_aot_helper_shl(i32 %h_a_value, i32 %h_a_count) #1 {
entry:
  br label %body
body:
  %t1 = and i32 %h_a_count, 31
  %t2 = shl i32 %h_a_value, %t1
  ret i32 %t2
}

define internal i32 @ks_encode_aot_helper_and_bits(i32 %h_a_a, i32 %h_a_b) #1 {
entry:
  br label %body
body:
  %t1 = and i32 %h_a_a, %h_a_b
  ret i32 %t1
}

define internal i32 @ks_encode_aot_helper_or_bits(i32 %h_a_a, i32 %h_a_b) #1 {
entry:
  br label %body
body:
  %t1 = or i32 %h_a_a, %h_a_b
  ret i32 %t1
}

define internal i32 @ks_encode_aot_helper_reversed(i32 %h_a_word) #1 {
entry:
  br label %body
body:
  %t1 = call i32 @ks_encode_aot_helper_u32(double 0x4038000000000000)
  %t2 = call i32 @ks_encode_aot_helper_shl(i32 %h_a_word, i32 %t1)
  %t3 = call i32 @ks_encode_aot_helper_u32(double 0x40EFE00000000000)
  %t4 = call i32 @ks_encode_aot_helper_and_bits(i32 %h_a_word, i32 %t3)
  %t5 = call i32 @ks_encode_aot_helper_u32(double 0x4020000000000000)
  %t6 = call i32 @ks_encode_aot_helper_shl(i32 %t4, i32 %t5)
  %t7 = call i32 @ks_encode_aot_helper_or_bits(i32 %t2, i32 %t6)
  %t8 = call i32 @ks_encode_aot_helper_u32(double 0x4020000000000000)
  %t9 = call i32 @ks_encode_aot_helper_shr(i32 %h_a_word, i32 %t8)
  %t10 = call i32 @ks_encode_aot_helper_u32(double 0x40EFE00000000000)
  %t11 = call i32 @ks_encode_aot_helper_and_bits(i32 %t9, i32 %t10)
  %t12 = call i32 @ks_encode_aot_helper_u32(double 0x4038000000000000)
  %t13 = call i32 @ks_encode_aot_helper_shr(i32 %h_a_word, i32 %t12)
  %t14 = call i32 @ks_encode_aot_helper_or_bits(i32 %t11, i32 %t13)
  %t15 = call i32 @ks_encode_aot_helper_or_bits(i32 %t7, i32 %t14)
  ret i32 %t15
}

define internal i32 @ks_07af12f296a4e582_encode_aot__neon_lua(ptr %L) #0 !dbg !5 {
entry:
  %slot6 = alloca i64, align 8
  %slot13 = alloca i32, align 4
  %slot21 = alloca i32, align 4
  %slot22 = alloca [4096 x i8], align 16
  %slot30 = alloca { ptr, i32, i32, i32, i32 }, align 8
  %slot36 = alloca i32, align 4
  %slot38 = alloca i32, align 4
  %slot47 = alloca i32, align 4
  %slot60 = alloca i32, align 4
  %slot75 = alloca i32, align 4
  %slot90 = alloca i32, align 4
  %slot94 = alloca i32, align 4
  %slot104 = alloca i32, align 4
  %slot114 = alloca i32, align 4
  %slot118 = alloca i32, align 4
  %slot468 = alloca i32, align 4
  %slot479 = alloca i32, align 4
  %slot490 = alloca i32, align 4
  %slot638 = alloca i32, align 4
  %slot649 = alloca i32, align 4
  %slot773 = alloca i32, align 4
  %slot784 = alloca i32, align 4
  br label %body
body:
  %t1 = load ptr, ptr @ks.rt, !dbg !6
  %t2 = call i32 @lua_checkstack(ptr %L, i32 7), !dbg !6
  %t3 = icmp eq i32 %t2, 0, !dbg !6
  br i1 %t3, label %lua.raise.1, label %lua.ok.2, !prof !7, !dbg !6
lua.raise.1:
  %t4 = getelementptr inbounds ptr, ptr %t1, i64 11, !dbg !6
  %rt.raise.5 = load ptr, ptr %t4, !invariant.load !8, !dbg !6
  call void %rt.raise.5(ptr %L, i64 1) nomerge, !dbg !6
  unreachable, !dbg !6
lua.ok.2:
  %t7 = call ptr @luaL_checklstring(ptr %L, i32 1, ptr %slot6), !dbg !6
  %t8 = load i64, ptr %slot6, !dbg !6
  %t9 = icmp ugt i64 %t8, 4294967295, !dbg !9
  br i1 %t9, label %lua.raise.3, label %lua.ok.4, !prof !7, !dbg !9
lua.raise.3:
  %t10 = getelementptr inbounds ptr, ptr %t1, i64 11, !dbg !9
  %rt.raise.11 = load ptr, ptr %t10, !invariant.load !8, !dbg !9
  call void %rt.raise.11(ptr %L, i64 2) nomerge, !dbg !9
  unreachable, !dbg !9
lua.ok.4:
  %t12 = trunc i64 %t8 to i32, !dbg !9
  store i32 %t12, ptr %slot13, !dbg !9
  %t14 = load i32, ptr %slot13, !dbg !10
  %t15 = load i32, ptr %slot13, !dbg !10
  %t16 = call i32 @ks_encode_aot_helper_u32(double 0x3FF0000000000000), !dbg !10
  %t17 = call i32 @ks_encode_aot_helper_shr(i32 %t15, i32 %t16), !dbg !10
  %t18 = call i32 @ks_encode_aot_helper_add(i32 %t14, i32 %t17), !dbg !10
  %t19 = call i32 @ks_encode_aot_helper_u32(double 0x4010000000000000), !dbg !10
  %t20 = call i32 @ks_encode_aot_helper_add(i32 %t18, i32 %t19), !dbg !10
  store i32 %t20, ptr %slot21, !dbg !10
  %t23 = call i32 @ks_encode_aot_helper_u32(double 0x4000000000000000), !dbg !11
  %t24 = zext i32 %t23 to i64, !dbg !11
  %t25 = load i32, ptr %slot21, !dbg !11
  %t26 = zext i32 %t25 to i64, !dbg !11
  %t27 = sext i32 2 to i64, !dbg !11
  %t28 = getelementptr inbounds ptr, ptr %t1, i64 47, !dbg !11
  %rt.builder_init.29 = load ptr, ptr %t28, !invariant.load !8, !dbg !11
  call void %rt.builder_init.29(ptr %L, ptr %slot22, i64 %t27, i64 0, i64 0, i64 %t24, i64 %t26, i64 0, i64 0, i64 0, i64 1), !dbg !11
  %t31 = load i32, ptr %slot21, !dbg !12
  %t32 = zext i32 %t31 to i64, !dbg !12
  %t33 = getelementptr inbounds ptr, ptr %t1, i64 38, !dbg !12
  %rt.scratch_u8_cached.34 = load ptr, ptr %t33, !invariant.load !8, !dbg !12
  call void %rt.scratch_u8_cached.34(ptr %L, ptr %slot30, i64 %t32), !dbg !12
  %t35 = call i32 @ks_encode_aot_helper_u32(double 0x0000000000000000), !dbg !13
  store i32 %t35, ptr %slot36, !dbg !13
  %t37 = call i32 @ks_encode_aot_helper_u32(double 0x0000000000000000), !dbg !14
  store i32 %t37, ptr %slot38, !dbg !14
  br label %while.head.5, !dbg !15
while.head.5:
  %t39 = load i32, ptr %slot36, !dbg !15
  %t40 = call i32 @ks_encode_aot_helper_u32(double 0x4028000000000000), !dbg !15
  %t41 = call i32 @ks_encode_aot_helper_add(i32 %t39, i32 %t40), !dbg !15
  %t42 = load i32, ptr %slot13, !dbg !15
  %t43 = icmp ule i32 %t41, %t42, !dbg !15
  br i1 %t43, label %while.body.6, label %while.end.7, !dbg !15
while.body.6:
  %t44 = load i32, ptr %slot36, !dbg !16
  %t45 = call i32 @ks_encode_aot_helper_u32(double 0x4000000000000000), !dbg !16
  %t46 = call i32 @ks_encode_aot_helper_shr(i32 %t44, i32 %t45), !dbg !16
  store i32 %t46, ptr %slot47, !dbg !16
  %t48 = load i32, ptr %slot47, !dbg !17
  %t49 = zext i32 %t48 to i64, !dbg !17
  %t50 = shl nuw i64 %t49, 2, !dbg !17
  %t51 = icmp ugt i64 %t50, %t8, !dbg !17
  %t52 = sub i64 %t8, %t50, !dbg !17
  %t53 = icmp ult i64 %t52, 4, !dbg !17
  %t54 = or i1 %t51, %t53, !dbg !17
  br i1 %t54, label %lua.raise.8, label %lua.ok.9, !prof !7, !dbg !17
lua.raise.8:
  %t55 = getelementptr inbounds ptr, ptr %t1, i64 11, !dbg !17
  %rt.raise.56 = load ptr, ptr %t55, !invariant.load !8, !dbg !17
  call void %rt.raise.56(ptr %L, i64 5) nomerge, !dbg !17
  unreachable, !dbg !17
lua.ok.9:
  %t57 = getelementptr inbounds i8, ptr %t7, i64 %t50, !dbg !17
  %t58 = load i32, ptr %t57, align 1, !dbg !17
  %t59 = call i32 @ks_encode_aot_helper_reversed(i32 %t58), !dbg !17
  store i32 %t59, ptr %slot60, !dbg !17
  %t61 = load i32, ptr %slot47, !dbg !18
  %t62 = call i32 @ks_encode_aot_helper_u32(double 0x3FF0000000000000), !dbg !18
  %t63 = call i32 @ks_encode_aot_helper_add(i32 %t61, i32 %t62), !dbg !18
  %t64 = zext i32 %t63 to i64, !dbg !18
  %t65 = shl nuw i64 %t64, 2, !dbg !18
  %t66 = icmp ugt i64 %t65, %t8, !dbg !18
  %t67 = sub i64 %t8, %t65, !dbg !18
  %t68 = icmp ult i64 %t67, 4, !dbg !18
  %t69 = or i1 %t66, %t68, !dbg !18
  br i1 %t69, label %lua.raise.10, label %lua.ok.11, !prof !7, !dbg !18
lua.raise.10:
  %t70 = getelementptr inbounds ptr, ptr %t1, i64 11, !dbg !18
  %rt.raise.71 = load ptr, ptr %t70, !invariant.load !8, !dbg !18
  call void %rt.raise.71(ptr %L, i64 5) nomerge, !dbg !18
  unreachable, !dbg !18
lua.ok.11:
  %t72 = getelementptr inbounds i8, ptr %t7, i64 %t65, !dbg !18
  %t73 = load i32, ptr %t72, align 1, !dbg !18
  %t74 = call i32 @ks_encode_aot_helper_reversed(i32 %t73), !dbg !18
  store i32 %t74, ptr %slot75, !dbg !18
  %t76 = load i32, ptr %slot47, !dbg !19
  %t77 = call i32 @ks_encode_aot_helper_u32(double 0x4000000000000000), !dbg !19
  %t78 = call i32 @ks_encode_aot_helper_add(i32 %t76, i32 %t77), !dbg !19
  %t79 = zext i32 %t78 to i64, !dbg !19
  %t80 = shl nuw i64 %t79, 2, !dbg !19
  %t81 = icmp ugt i64 %t80, %t8, !dbg !19
  %t82 = sub i64 %t8, %t80, !dbg !19
  %t83 = icmp ult i64 %t82, 4, !dbg !19
  %t84 = or i1 %t81, %t83, !dbg !19
  br i1 %t84, label %lua.raise.12, label %lua.ok.13, !prof !7, !dbg !19
lua.raise.12:
  %t85 = getelementptr inbounds ptr, ptr %t1, i64 11, !dbg !19
  %rt.raise.86 = load ptr, ptr %t85, !invariant.load !8, !dbg !19
  call void %rt.raise.86(ptr %L, i64 5) nomerge, !dbg !19
  unreachable, !dbg !19
lua.ok.13:
  %t87 = getelementptr inbounds i8, ptr %t7, i64 %t80, !dbg !19
  %t88 = load i32, ptr %t87, align 1, !dbg !19
  %t89 = call i32 @ks_encode_aot_helper_reversed(i32 %t88), !dbg !19
  store i32 %t89, ptr %slot90, !dbg !19
  %t91 = load i32, ptr %slot60, !dbg !20
  %t92 = call i32 @ks_encode_aot_helper_u32(double 0x4020000000000000), !dbg !20
  %t93 = call i32 @ks_encode_aot_helper_shr(i32 %t91, i32 %t92), !dbg !20
  store i32 %t93, ptr %slot94, !dbg !20
  %t95 = load i32, ptr %slot60, !dbg !21
  %t96 = call i32 @ks_encode_aot_helper_u32(double 0x406FE00000000000), !dbg !21
  %t97 = call i32 @ks_encode_aot_helper_and_bits(i32 %t95, i32 %t96), !dbg !21
  %t98 = call i32 @ks_encode_aot_helper_u32(double 0x4030000000000000), !dbg !21
  %t99 = call i32 @ks_encode_aot_helper_shl(i32 %t97, i32 %t98), !dbg !21
  %t100 = load i32, ptr %slot75, !dbg !21
  %t101 = call i32 @ks_encode_aot_helper_u32(double 0x4030000000000000), !dbg !21
  %t102 = call i32 @ks_encode_aot_helper_shr(i32 %t100, i32 %t101), !dbg !21
  %t103 = call i32 @ks_encode_aot_helper_or_bits(i32 %t99, i32 %t102), !dbg !21
  store i32 %t103, ptr %slot104, !dbg !21
  %t105 = load i32, ptr %slot75, !dbg !22
  %t106 = call i32 @ks_encode_aot_helper_u32(double 0x40EFFFE000000000), !dbg !22
  %t107 = call i32 @ks_encode_aot_helper_and_bits(i32 %t105, i32 %t106), !dbg !22
  %t108 = call i32 @ks_encode_aot_helper_u32(double 0x4020000000000000), !dbg !22
  %t109 = call i32 @ks_encode_aot_helper_shl(i32 %t107, i32 %t108), !dbg !22
  %t110 = load i32, ptr %slot90, !dbg !22
  %t111 = call i32 @ks_encode_aot_helper_u32(double 0x4038000000000000), !dbg !22
  %t112 = call i32 @ks_encode_aot_helper_shr(i32 %t110, i32 %t111), !dbg !22
  %t113 = call i32 @ks_encode_aot_helper_or_bits(i32 %t109, i32 %t112), !dbg !22
  store i32 %t113, ptr %slot114, !dbg !22
  %t115 = load i32, ptr %slot90, !dbg !23
  %t116 = call i32 @ks_encode_aot_helper_u32(double 0x416FFFFFE0000000), !dbg !23
  %t117 = call i32 @ks_encode_aot_helper_and_bits(i32 %t115, i32 %t116), !dbg !23
  store i32 %t117, ptr %slot118, !dbg !23
  %t119 = getelementptr inbounds { ptr, i32, i32, i32, i32 }, ptr %slot30, i32 0, i32 2, !dbg !24
  %t120 = load i32, ptr %slot38, !dbg !24
  %t121 = load i32, ptr %slot94, !dbg !24
  %t122 = call i32 @ks_encode_aot_helper_u32(double 0x4032000000000000), !dbg !24
  %t123 = call i32 @ks_encode_aot_helper_shr(i32 %t121, i32 %t122), !dbg !24
  %t124 = call i32 @ks_encode_aot_helper_u32(double 0x404F800000000000), !dbg !24
  %t125 = call i32 @ks_encode_aot_helper_and_bits(i32 %t123, i32 %t124), !dbg !24
  %t126 = zext i32 %t125 to i64, !dbg !24
  %t127 = icmp uge i64 %t126, 64, !dbg !24
  br i1 %t127, label %lua.raise.14, label %lua.ok.15, !prof !7, !dbg !24
lua.raise.14:
  %t128 = getelementptr inbounds ptr, ptr %t1, i64 11, !dbg !24
  %rt.raise.129 = load ptr, ptr %t128, !invariant.load !8, !dbg !24
  call void %rt.raise.129(ptr %L, i64 3) nomerge, !dbg !24
  unreachable, !dbg !24
lua.ok.15:
  %t130 = getelementptr inbounds i8, ptr @nupp.bytes.1, i64 %t126, !dbg !24
  %t131 = load i8, ptr %t130, !dbg !24
  %t132 = zext i8 %t131 to i32, !dbg !24
  %t133 = load i32, ptr %slot94, !dbg !24
  %t134 = call i32 @ks_encode_aot_helper_u32(double 0x4028000000000000), !dbg !24
  %t135 = call i32 @ks_encode_aot_helper_shr(i32 %t133, i32 %t134), !dbg !24
  %t136 = call i32 @ks_encode_aot_helper_u32(double 0x404F800000000000), !dbg !24
  %t137 = call i32 @ks_encode_aot_helper_and_bits(i32 %t135, i32 %t136), !dbg !24
  %t138 = zext i32 %t137 to i64, !dbg !24
  %t139 = icmp uge i64 %t138, 64, !dbg !24
  br i1 %t139, label %lua.raise.16, label %lua.ok.17, !prof !7, !dbg !24
lua.raise.16:
  %t140 = getelementptr inbounds ptr, ptr %t1, i64 11, !dbg !24
  %rt.raise.141 = load ptr, ptr %t140, !invariant.load !8, !dbg !24
  call void %rt.raise.141(ptr %L, i64 3) nomerge, !dbg !24
  unreachable, !dbg !24
lua.ok.17:
  %t142 = getelementptr inbounds i8, ptr @nupp.bytes.1, i64 %t138, !dbg !24
  %t143 = load i8, ptr %t142, !dbg !24
  %t144 = zext i8 %t143 to i32, !dbg !24
  %t145 = call i32 @ks_encode_aot_helper_u32(double 0x4020000000000000), !dbg !24
  %t146 = call i32 @ks_encode_aot_helper_shl(i32 %t144, i32 %t145), !dbg !24
  %t147 = call i32 @ks_encode_aot_helper_or_bits(i32 %t132, i32 %t146), !dbg !24
  %t148 = load i32, ptr %slot94, !dbg !24
  %t149 = call i32 @ks_encode_aot_helper_u32(double 0x4018000000000000), !dbg !24
  %t150 = call i32 @ks_encode_aot_helper_shr(i32 %t148, i32 %t149), !dbg !24
  %t151 = call i32 @ks_encode_aot_helper_u32(double 0x404F800000000000), !dbg !24
  %t152 = call i32 @ks_encode_aot_helper_and_bits(i32 %t150, i32 %t151), !dbg !24
  %t153 = zext i32 %t152 to i64, !dbg !24
  %t154 = icmp uge i64 %t153, 64, !dbg !24
  br i1 %t154, label %lua.raise.18, label %lua.ok.19, !prof !7, !dbg !24
lua.raise.18:
  %t155 = getelementptr inbounds ptr, ptr %t1, i64 11, !dbg !24
  %rt.raise.156 = load ptr, ptr %t155, !invariant.load !8, !dbg !24
  call void %rt.raise.156(ptr %L, i64 3) nomerge, !dbg !24
  unreachable, !dbg !24
lua.ok.19:
  %t157 = getelementptr inbounds i8, ptr @nupp.bytes.1, i64 %t153, !dbg !24
  %t158 = load i8, ptr %t157, !dbg !24
  %t159 = zext i8 %t158 to i32, !dbg !24
  %t160 = call i32 @ks_encode_aot_helper_u32(double 0x4030000000000000), !dbg !24
  %t161 = call i32 @ks_encode_aot_helper_shl(i32 %t159, i32 %t160), !dbg !24
  %t162 = load i32, ptr %slot94, !dbg !24
  %t163 = call i32 @ks_encode_aot_helper_u32(double 0x404F800000000000), !dbg !24
  %t164 = call i32 @ks_encode_aot_helper_and_bits(i32 %t162, i32 %t163), !dbg !24
  %t165 = zext i32 %t164 to i64, !dbg !24
  %t166 = icmp uge i64 %t165, 64, !dbg !24
  br i1 %t166, label %lua.raise.20, label %lua.ok.21, !prof !7, !dbg !24
lua.raise.20:
  %t167 = getelementptr inbounds ptr, ptr %t1, i64 11, !dbg !24
  %rt.raise.168 = load ptr, ptr %t167, !invariant.load !8, !dbg !24
  call void %rt.raise.168(ptr %L, i64 3) nomerge, !dbg !24
  unreachable, !dbg !24
lua.ok.21:
  %t169 = getelementptr inbounds i8, ptr @nupp.bytes.1, i64 %t165, !dbg !24
  %t170 = load i8, ptr %t169, !dbg !24
  %t171 = zext i8 %t170 to i32, !dbg !24
  %t172 = call i32 @ks_encode_aot_helper_u32(double 0x4038000000000000), !dbg !24
  %t173 = call i32 @ks_encode_aot_helper_shl(i32 %t171, i32 %t172), !dbg !24
  %t174 = call i32 @ks_encode_aot_helper_or_bits(i32 %t161, i32 %t173), !dbg !24
  %t175 = call i32 @ks_encode_aot_helper_or_bits(i32 %t147, i32 %t174), !dbg !24
  %t176 = load i32, ptr %t119, !dbg !24
  %t177 = getelementptr inbounds { ptr, i32, i32, i32, i32 }, ptr %slot30, i32 0, i32 1, !dbg !24
  %t178 = load i32, ptr %t177, !dbg !24
  %t179 = icmp ugt i32 %t120, %t176, !dbg !24
  %t180 = icmp ugt i32 %t120, %t178, !dbg !24
  %t181 = sub i32 %t178, %t120, !dbg !24
  %t182 = icmp ult i32 %t181, 4, !dbg !24
  %t183 = or i1 %t179, %t180, !dbg !24
  %t184 = or i1 %t183, %t182, !dbg !24
  br i1 %t184, label %lua.raise.22, label %lua.ok.23, !prof !7, !dbg !24
lua.raise.22:
  %t185 = getelementptr inbounds ptr, ptr %t1, i64 11, !dbg !24
  %rt.raise.186 = load ptr, ptr %t185, !invariant.load !8, !dbg !24
  call void %rt.raise.186(ptr %L, i64 11) nomerge, !dbg !24
  unreachable, !dbg !24
lua.ok.23:
  %t187 = icmp ult i32 %t120, %t176, !dbg !24
  %t188 = sub i32 %t176, %t120, !dbg !24
  %t189 = icmp ult i32 %t188, 4, !dbg !24
  %t190 = and i1 %t187, %t189, !dbg !24
  br i1 %t190, label %lua.raise.24, label %lua.ok.25, !prof !7, !dbg !24
lua.raise.24:
  %t191 = getelementptr inbounds ptr, ptr %t1, i64 11, !dbg !24
  %rt.raise.192 = load ptr, ptr %t191, !invariant.load !8, !dbg !24
  call void %rt.raise.192(ptr %L, i64 12) nomerge, !dbg !24
  unreachable, !dbg !24
lua.ok.25:
  %t193 = icmp eq i32 %t120, %t176, !dbg !24
  %t194 = add i32 %t176, 4, !dbg !24
  %t195 = select i1 %t193, i32 %t194, i32 %t176, !dbg !24
  store i32 %t195, ptr %t119, !dbg !24
  %t196 = getelementptr inbounds { ptr, i32, i32, i32, i32 }, ptr %slot30, i32 0, i32 0, !dbg !24
  %t197 = load ptr, ptr %t196, !dbg !24
  %t198 = zext i32 %t120 to i64, !dbg !24
  %t199 = getelementptr inbounds i8, ptr %t197, i64 %t198, !dbg !24
  store i32 %t175, ptr %t199, align 1, !dbg !24
  %t200 = getelementptr inbounds { ptr, i32, i32, i32, i32 }, ptr %slot30, i32 0, i32 2, !dbg !25
  %t201 = load i32, ptr %slot38, !dbg !25
  %t202 = call i32 @ks_encode_aot_helper_u32(double 0x4010000000000000), !dbg !25
  %t203 = call i32 @ks_encode_aot_helper_add(i32 %t201, i32 %t202), !dbg !25
  %t204 = load i32, ptr %slot104, !dbg !25
  %t205 = call i32 @ks_encode_aot_helper_u32(double 0x4032000000000000), !dbg !25
  %t206 = call i32 @ks_encode_aot_helper_shr(i32 %t204, i32 %t205), !dbg !25
  %t207 = call i32 @ks_encode_aot_helper_u32(double 0x404F800000000000), !dbg !25
  %t208 = call i32 @ks_encode_aot_helper_and_bits(i32 %t206, i32 %t207), !dbg !25
  %t209 = zext i32 %t208 to i64, !dbg !25
  %t210 = icmp uge i64 %t209, 64, !dbg !25
  br i1 %t210, label %lua.raise.26, label %lua.ok.27, !prof !7, !dbg !25
lua.raise.26:
  %t211 = getelementptr inbounds ptr, ptr %t1, i64 11, !dbg !25
  %rt.raise.212 = load ptr, ptr %t211, !invariant.load !8, !dbg !25
  call void %rt.raise.212(ptr %L, i64 3) nomerge, !dbg !25
  unreachable, !dbg !25
lua.ok.27:
  %t213 = getelementptr inbounds i8, ptr @nupp.bytes.1, i64 %t209, !dbg !25
  %t214 = load i8, ptr %t213, !dbg !25
  %t215 = zext i8 %t214 to i32, !dbg !25
  %t216 = load i32, ptr %slot104, !dbg !25
  %t217 = call i32 @ks_encode_aot_helper_u32(double 0x4028000000000000), !dbg !25
  %t218 = call i32 @ks_encode_aot_helper_shr(i32 %t216, i32 %t217), !dbg !25
  %t219 = call i32 @ks_encode_aot_helper_u32(double 0x404F800000000000), !dbg !25
  %t220 = call i32 @ks_encode_aot_helper_and_bits(i32 %t218, i32 %t219), !dbg !25
  %t221 = zext i32 %t220 to i64, !dbg !25
  %t222 = icmp uge i64 %t221, 64, !dbg !25
  br i1 %t222, label %lua.raise.28, label %lua.ok.29, !prof !7, !dbg !25
lua.raise.28:
  %t223 = getelementptr inbounds ptr, ptr %t1, i64 11, !dbg !25
  %rt.raise.224 = load ptr, ptr %t223, !invariant.load !8, !dbg !25
  call void %rt.raise.224(ptr %L, i64 3) nomerge, !dbg !25
  unreachable, !dbg !25
lua.ok.29:
  %t225 = getelementptr inbounds i8, ptr @nupp.bytes.1, i64 %t221, !dbg !25
  %t226 = load i8, ptr %t225, !dbg !25
  %t227 = zext i8 %t226 to i32, !dbg !25
  %t228 = call i32 @ks_encode_aot_helper_u32(double 0x4020000000000000), !dbg !25
  %t229 = call i32 @ks_encode_aot_helper_shl(i32 %t227, i32 %t228), !dbg !25
  %t230 = call i32 @ks_encode_aot_helper_or_bits(i32 %t215, i32 %t229), !dbg !25
  %t231 = load i32, ptr %slot104, !dbg !25
  %t232 = call i32 @ks_encode_aot_helper_u32(double 0x4018000000000000), !dbg !25
  %t233 = call i32 @ks_encode_aot_helper_shr(i32 %t231, i32 %t232), !dbg !25
  %t234 = call i32 @ks_encode_aot_helper_u32(double 0x404F800000000000), !dbg !25
  %t235 = call i32 @ks_encode_aot_helper_and_bits(i32 %t233, i32 %t234), !dbg !25
  %t236 = zext i32 %t235 to i64, !dbg !25
  %t237 = icmp uge i64 %t236, 64, !dbg !25
  br i1 %t237, label %lua.raise.30, label %lua.ok.31, !prof !7, !dbg !25
lua.raise.30:
  %t238 = getelementptr inbounds ptr, ptr %t1, i64 11, !dbg !25
  %rt.raise.239 = load ptr, ptr %t238, !invariant.load !8, !dbg !25
  call void %rt.raise.239(ptr %L, i64 3) nomerge, !dbg !25
  unreachable, !dbg !25
lua.ok.31:
  %t240 = getelementptr inbounds i8, ptr @nupp.bytes.1, i64 %t236, !dbg !25
  %t241 = load i8, ptr %t240, !dbg !25
  %t242 = zext i8 %t241 to i32, !dbg !25
  %t243 = call i32 @ks_encode_aot_helper_u32(double 0x4030000000000000), !dbg !25
  %t244 = call i32 @ks_encode_aot_helper_shl(i32 %t242, i32 %t243), !dbg !25
  %t245 = load i32, ptr %slot104, !dbg !25
  %t246 = call i32 @ks_encode_aot_helper_u32(double 0x404F800000000000), !dbg !25
  %t247 = call i32 @ks_encode_aot_helper_and_bits(i32 %t245, i32 %t246), !dbg !25
  %t248 = zext i32 %t247 to i64, !dbg !25
  %t249 = icmp uge i64 %t248, 64, !dbg !25
  br i1 %t249, label %lua.raise.32, label %lua.ok.33, !prof !7, !dbg !25
lua.raise.32:
  %t250 = getelementptr inbounds ptr, ptr %t1, i64 11, !dbg !25
  %rt.raise.251 = load ptr, ptr %t250, !invariant.load !8, !dbg !25
  call void %rt.raise.251(ptr %L, i64 3) nomerge, !dbg !25
  unreachable, !dbg !25
lua.ok.33:
  %t252 = getelementptr inbounds i8, ptr @nupp.bytes.1, i64 %t248, !dbg !25
  %t253 = load i8, ptr %t252, !dbg !25
  %t254 = zext i8 %t253 to i32, !dbg !25
  %t255 = call i32 @ks_encode_aot_helper_u32(double 0x4038000000000000), !dbg !25
  %t256 = call i32 @ks_encode_aot_helper_shl(i32 %t254, i32 %t255), !dbg !25
  %t257 = call i32 @ks_encode_aot_helper_or_bits(i32 %t244, i32 %t256), !dbg !25
  %t258 = call i32 @ks_encode_aot_helper_or_bits(i32 %t230, i32 %t257), !dbg !25
  %t259 = load i32, ptr %t200, !dbg !25
  %t260 = getelementptr inbounds { ptr, i32, i32, i32, i32 }, ptr %slot30, i32 0, i32 1, !dbg !25
  %t261 = load i32, ptr %t260, !dbg !25
  %t262 = icmp ugt i32 %t203, %t259, !dbg !25
  %t263 = icmp ugt i32 %t203, %t261, !dbg !25
  %t264 = sub i32 %t261, %t203, !dbg !25
  %t265 = icmp ult i32 %t264, 4, !dbg !25
  %t266 = or i1 %t262, %t263, !dbg !25
  %t267 = or i1 %t266, %t265, !dbg !25
  br i1 %t267, label %lua.raise.34, label %lua.ok.35, !prof !7, !dbg !25
lua.raise.34:
  %t268 = getelementptr inbounds ptr, ptr %t1, i64 11, !dbg !25
  %rt.raise.269 = load ptr, ptr %t268, !invariant.load !8, !dbg !25
  call void %rt.raise.269(ptr %L, i64 11) nomerge, !dbg !25
  unreachable, !dbg !25
lua.ok.35:
  %t270 = icmp ult i32 %t203, %t259, !dbg !25
  %t271 = sub i32 %t259, %t203, !dbg !25
  %t272 = icmp ult i32 %t271, 4, !dbg !25
  %t273 = and i1 %t270, %t272, !dbg !25
  br i1 %t273, label %lua.raise.36, label %lua.ok.37, !prof !7, !dbg !25
lua.raise.36:
  %t274 = getelementptr inbounds ptr, ptr %t1, i64 11, !dbg !25
  %rt.raise.275 = load ptr, ptr %t274, !invariant.load !8, !dbg !25
  call void %rt.raise.275(ptr %L, i64 12) nomerge, !dbg !25
  unreachable, !dbg !25
lua.ok.37:
  %t276 = icmp eq i32 %t203, %t259, !dbg !25
  %t277 = add i32 %t259, 4, !dbg !25
  %t278 = select i1 %t276, i32 %t277, i32 %t259, !dbg !25
  store i32 %t278, ptr %t200, !dbg !25
  %t279 = getelementptr inbounds { ptr, i32, i32, i32, i32 }, ptr %slot30, i32 0, i32 0, !dbg !25
  %t280 = load ptr, ptr %t279, !dbg !25
  %t281 = zext i32 %t203 to i64, !dbg !25
  %t282 = getelementptr inbounds i8, ptr %t280, i64 %t281, !dbg !25
  store i32 %t258, ptr %t282, align 1, !dbg !25
  %t283 = getelementptr inbounds { ptr, i32, i32, i32, i32 }, ptr %slot30, i32 0, i32 2, !dbg !26
  %t284 = load i32, ptr %slot38, !dbg !26
  %t285 = call i32 @ks_encode_aot_helper_u32(double 0x4020000000000000), !dbg !26
  %t286 = call i32 @ks_encode_aot_helper_add(i32 %t284, i32 %t285), !dbg !26
  %t287 = load i32, ptr %slot114, !dbg !26
  %t288 = call i32 @ks_encode_aot_helper_u32(double 0x4032000000000000), !dbg !26
  %t289 = call i32 @ks_encode_aot_helper_shr(i32 %t287, i32 %t288), !dbg !26
  %t290 = call i32 @ks_encode_aot_helper_u32(double 0x404F800000000000), !dbg !26
  %t291 = call i32 @ks_encode_aot_helper_and_bits(i32 %t289, i32 %t290), !dbg !26
  %t292 = zext i32 %t291 to i64, !dbg !26
  %t293 = icmp uge i64 %t292, 64, !dbg !26
  br i1 %t293, label %lua.raise.38, label %lua.ok.39, !prof !7, !dbg !26
lua.raise.38:
  %t294 = getelementptr inbounds ptr, ptr %t1, i64 11, !dbg !26
  %rt.raise.295 = load ptr, ptr %t294, !invariant.load !8, !dbg !26
  call void %rt.raise.295(ptr %L, i64 3) nomerge, !dbg !26
  unreachable, !dbg !26
lua.ok.39:
  %t296 = getelementptr inbounds i8, ptr @nupp.bytes.1, i64 %t292, !dbg !26
  %t297 = load i8, ptr %t296, !dbg !26
  %t298 = zext i8 %t297 to i32, !dbg !26
  %t299 = load i32, ptr %slot114, !dbg !26
  %t300 = call i32 @ks_encode_aot_helper_u32(double 0x4028000000000000), !dbg !26
  %t301 = call i32 @ks_encode_aot_helper_shr(i32 %t299, i32 %t300), !dbg !26
  %t302 = call i32 @ks_encode_aot_helper_u32(double 0x404F800000000000), !dbg !26
  %t303 = call i32 @ks_encode_aot_helper_and_bits(i32 %t301, i32 %t302), !dbg !26
  %t304 = zext i32 %t303 to i64, !dbg !26
  %t305 = icmp uge i64 %t304, 64, !dbg !26
  br i1 %t305, label %lua.raise.40, label %lua.ok.41, !prof !7, !dbg !26
lua.raise.40:
  %t306 = getelementptr inbounds ptr, ptr %t1, i64 11, !dbg !26
  %rt.raise.307 = load ptr, ptr %t306, !invariant.load !8, !dbg !26
  call void %rt.raise.307(ptr %L, i64 3) nomerge, !dbg !26
  unreachable, !dbg !26
lua.ok.41:
  %t308 = getelementptr inbounds i8, ptr @nupp.bytes.1, i64 %t304, !dbg !26
  %t309 = load i8, ptr %t308, !dbg !26
  %t310 = zext i8 %t309 to i32, !dbg !26
  %t311 = call i32 @ks_encode_aot_helper_u32(double 0x4020000000000000), !dbg !26
  %t312 = call i32 @ks_encode_aot_helper_shl(i32 %t310, i32 %t311), !dbg !26
  %t313 = call i32 @ks_encode_aot_helper_or_bits(i32 %t298, i32 %t312), !dbg !26
  %t314 = load i32, ptr %slot114, !dbg !26
  %t315 = call i32 @ks_encode_aot_helper_u32(double 0x4018000000000000), !dbg !26
  %t316 = call i32 @ks_encode_aot_helper_shr(i32 %t314, i32 %t315), !dbg !26
  %t317 = call i32 @ks_encode_aot_helper_u32(double 0x404F800000000000), !dbg !26
  %t318 = call i32 @ks_encode_aot_helper_and_bits(i32 %t316, i32 %t317), !dbg !26
  %t319 = zext i32 %t318 to i64, !dbg !26
  %t320 = icmp uge i64 %t319, 64, !dbg !26
  br i1 %t320, label %lua.raise.42, label %lua.ok.43, !prof !7, !dbg !26
lua.raise.42:
  %t321 = getelementptr inbounds ptr, ptr %t1, i64 11, !dbg !26
  %rt.raise.322 = load ptr, ptr %t321, !invariant.load !8, !dbg !26
  call void %rt.raise.322(ptr %L, i64 3) nomerge, !dbg !26
  unreachable, !dbg !26
lua.ok.43:
  %t323 = getelementptr inbounds i8, ptr @nupp.bytes.1, i64 %t319, !dbg !26
  %t324 = load i8, ptr %t323, !dbg !26
  %t325 = zext i8 %t324 to i32, !dbg !26
  %t326 = call i32 @ks_encode_aot_helper_u32(double 0x4030000000000000), !dbg !26
  %t327 = call i32 @ks_encode_aot_helper_shl(i32 %t325, i32 %t326), !dbg !26
  %t328 = load i32, ptr %slot114, !dbg !26
  %t329 = call i32 @ks_encode_aot_helper_u32(double 0x404F800000000000), !dbg !26
  %t330 = call i32 @ks_encode_aot_helper_and_bits(i32 %t328, i32 %t329), !dbg !26
  %t331 = zext i32 %t330 to i64, !dbg !26
  %t332 = icmp uge i64 %t331, 64, !dbg !26
  br i1 %t332, label %lua.raise.44, label %lua.ok.45, !prof !7, !dbg !26
lua.raise.44:
  %t333 = getelementptr inbounds ptr, ptr %t1, i64 11, !dbg !26
  %rt.raise.334 = load ptr, ptr %t333, !invariant.load !8, !dbg !26
  call void %rt.raise.334(ptr %L, i64 3) nomerge, !dbg !26
  unreachable, !dbg !26
lua.ok.45:
  %t335 = getelementptr inbounds i8, ptr @nupp.bytes.1, i64 %t331, !dbg !26
  %t336 = load i8, ptr %t335, !dbg !26
  %t337 = zext i8 %t336 to i32, !dbg !26
  %t338 = call i32 @ks_encode_aot_helper_u32(double 0x4038000000000000), !dbg !26
  %t339 = call i32 @ks_encode_aot_helper_shl(i32 %t337, i32 %t338), !dbg !26
  %t340 = call i32 @ks_encode_aot_helper_or_bits(i32 %t327, i32 %t339), !dbg !26
  %t341 = call i32 @ks_encode_aot_helper_or_bits(i32 %t313, i32 %t340), !dbg !26
  %t342 = load i32, ptr %t283, !dbg !26
  %t343 = getelementptr inbounds { ptr, i32, i32, i32, i32 }, ptr %slot30, i32 0, i32 1, !dbg !26
  %t344 = load i32, ptr %t343, !dbg !26
  %t345 = icmp ugt i32 %t286, %t342, !dbg !26
  %t346 = icmp ugt i32 %t286, %t344, !dbg !26
  %t347 = sub i32 %t344, %t286, !dbg !26
  %t348 = icmp ult i32 %t347, 4, !dbg !26
  %t349 = or i1 %t345, %t346, !dbg !26
  %t350 = or i1 %t349, %t348, !dbg !26
  br i1 %t350, label %lua.raise.46, label %lua.ok.47, !prof !7, !dbg !26
lua.raise.46:
  %t351 = getelementptr inbounds ptr, ptr %t1, i64 11, !dbg !26
  %rt.raise.352 = load ptr, ptr %t351, !invariant.load !8, !dbg !26
  call void %rt.raise.352(ptr %L, i64 11) nomerge, !dbg !26
  unreachable, !dbg !26
lua.ok.47:
  %t353 = icmp ult i32 %t286, %t342, !dbg !26
  %t354 = sub i32 %t342, %t286, !dbg !26
  %t355 = icmp ult i32 %t354, 4, !dbg !26
  %t356 = and i1 %t353, %t355, !dbg !26
  br i1 %t356, label %lua.raise.48, label %lua.ok.49, !prof !7, !dbg !26
lua.raise.48:
  %t357 = getelementptr inbounds ptr, ptr %t1, i64 11, !dbg !26
  %rt.raise.358 = load ptr, ptr %t357, !invariant.load !8, !dbg !26
  call void %rt.raise.358(ptr %L, i64 12) nomerge, !dbg !26
  unreachable, !dbg !26
lua.ok.49:
  %t359 = icmp eq i32 %t286, %t342, !dbg !26
  %t360 = add i32 %t342, 4, !dbg !26
  %t361 = select i1 %t359, i32 %t360, i32 %t342, !dbg !26
  store i32 %t361, ptr %t283, !dbg !26
  %t362 = getelementptr inbounds { ptr, i32, i32, i32, i32 }, ptr %slot30, i32 0, i32 0, !dbg !26
  %t363 = load ptr, ptr %t362, !dbg !26
  %t364 = zext i32 %t286 to i64, !dbg !26
  %t365 = getelementptr inbounds i8, ptr %t363, i64 %t364, !dbg !26
  store i32 %t341, ptr %t365, align 1, !dbg !26
  %t366 = getelementptr inbounds { ptr, i32, i32, i32, i32 }, ptr %slot30, i32 0, i32 2, !dbg !27
  %t367 = load i32, ptr %slot38, !dbg !27
  %t368 = call i32 @ks_encode_aot_helper_u32(double 0x4028000000000000), !dbg !27
  %t369 = call i32 @ks_encode_aot_helper_add(i32 %t367, i32 %t368), !dbg !27
  %t370 = load i32, ptr %slot118, !dbg !27
  %t371 = call i32 @ks_encode_aot_helper_u32(double 0x4032000000000000), !dbg !27
  %t372 = call i32 @ks_encode_aot_helper_shr(i32 %t370, i32 %t371), !dbg !27
  %t373 = call i32 @ks_encode_aot_helper_u32(double 0x404F800000000000), !dbg !27
  %t374 = call i32 @ks_encode_aot_helper_and_bits(i32 %t372, i32 %t373), !dbg !27
  %t375 = zext i32 %t374 to i64, !dbg !27
  %t376 = icmp uge i64 %t375, 64, !dbg !27
  br i1 %t376, label %lua.raise.50, label %lua.ok.51, !prof !7, !dbg !27
lua.raise.50:
  %t377 = getelementptr inbounds ptr, ptr %t1, i64 11, !dbg !27
  %rt.raise.378 = load ptr, ptr %t377, !invariant.load !8, !dbg !27
  call void %rt.raise.378(ptr %L, i64 3) nomerge, !dbg !27
  unreachable, !dbg !27
lua.ok.51:
  %t379 = getelementptr inbounds i8, ptr @nupp.bytes.1, i64 %t375, !dbg !27
  %t380 = load i8, ptr %t379, !dbg !27
  %t381 = zext i8 %t380 to i32, !dbg !27
  %t382 = load i32, ptr %slot118, !dbg !27
  %t383 = call i32 @ks_encode_aot_helper_u32(double 0x4028000000000000), !dbg !27
  %t384 = call i32 @ks_encode_aot_helper_shr(i32 %t382, i32 %t383), !dbg !27
  %t385 = call i32 @ks_encode_aot_helper_u32(double 0x404F800000000000), !dbg !27
  %t386 = call i32 @ks_encode_aot_helper_and_bits(i32 %t384, i32 %t385), !dbg !27
  %t387 = zext i32 %t386 to i64, !dbg !27
  %t388 = icmp uge i64 %t387, 64, !dbg !27
  br i1 %t388, label %lua.raise.52, label %lua.ok.53, !prof !7, !dbg !27
lua.raise.52:
  %t389 = getelementptr inbounds ptr, ptr %t1, i64 11, !dbg !27
  %rt.raise.390 = load ptr, ptr %t389, !invariant.load !8, !dbg !27
  call void %rt.raise.390(ptr %L, i64 3) nomerge, !dbg !27
  unreachable, !dbg !27
lua.ok.53:
  %t391 = getelementptr inbounds i8, ptr @nupp.bytes.1, i64 %t387, !dbg !27
  %t392 = load i8, ptr %t391, !dbg !27
  %t393 = zext i8 %t392 to i32, !dbg !27
  %t394 = call i32 @ks_encode_aot_helper_u32(double 0x4020000000000000), !dbg !27
  %t395 = call i32 @ks_encode_aot_helper_shl(i32 %t393, i32 %t394), !dbg !27
  %t396 = call i32 @ks_encode_aot_helper_or_bits(i32 %t381, i32 %t395), !dbg !27
  %t397 = load i32, ptr %slot118, !dbg !27
  %t398 = call i32 @ks_encode_aot_helper_u32(double 0x4018000000000000), !dbg !27
  %t399 = call i32 @ks_encode_aot_helper_shr(i32 %t397, i32 %t398), !dbg !27
  %t400 = call i32 @ks_encode_aot_helper_u32(double 0x404F800000000000), !dbg !27
  %t401 = call i32 @ks_encode_aot_helper_and_bits(i32 %t399, i32 %t400), !dbg !27
  %t402 = zext i32 %t401 to i64, !dbg !27
  %t403 = icmp uge i64 %t402, 64, !dbg !27
  br i1 %t403, label %lua.raise.54, label %lua.ok.55, !prof !7, !dbg !27
lua.raise.54:
  %t404 = getelementptr inbounds ptr, ptr %t1, i64 11, !dbg !27
  %rt.raise.405 = load ptr, ptr %t404, !invariant.load !8, !dbg !27
  call void %rt.raise.405(ptr %L, i64 3) nomerge, !dbg !27
  unreachable, !dbg !27
lua.ok.55:
  %t406 = getelementptr inbounds i8, ptr @nupp.bytes.1, i64 %t402, !dbg !27
  %t407 = load i8, ptr %t406, !dbg !27
  %t408 = zext i8 %t407 to i32, !dbg !27
  %t409 = call i32 @ks_encode_aot_helper_u32(double 0x4030000000000000), !dbg !27
  %t410 = call i32 @ks_encode_aot_helper_shl(i32 %t408, i32 %t409), !dbg !27
  %t411 = load i32, ptr %slot118, !dbg !27
  %t412 = call i32 @ks_encode_aot_helper_u32(double 0x404F800000000000), !dbg !27
  %t413 = call i32 @ks_encode_aot_helper_and_bits(i32 %t411, i32 %t412), !dbg !27
  %t414 = zext i32 %t413 to i64, !dbg !27
  %t415 = icmp uge i64 %t414, 64, !dbg !27
  br i1 %t415, label %lua.raise.56, label %lua.ok.57, !prof !7, !dbg !27
lua.raise.56:
  %t416 = getelementptr inbounds ptr, ptr %t1, i64 11, !dbg !27
  %rt.raise.417 = load ptr, ptr %t416, !invariant.load !8, !dbg !27
  call void %rt.raise.417(ptr %L, i64 3) nomerge, !dbg !27
  unreachable, !dbg !27
lua.ok.57:
  %t418 = getelementptr inbounds i8, ptr @nupp.bytes.1, i64 %t414, !dbg !27
  %t419 = load i8, ptr %t418, !dbg !27
  %t420 = zext i8 %t419 to i32, !dbg !27
  %t421 = call i32 @ks_encode_aot_helper_u32(double 0x4038000000000000), !dbg !27
  %t422 = call i32 @ks_encode_aot_helper_shl(i32 %t420, i32 %t421), !dbg !27
  %t423 = call i32 @ks_encode_aot_helper_or_bits(i32 %t410, i32 %t422), !dbg !27
  %t424 = call i32 @ks_encode_aot_helper_or_bits(i32 %t396, i32 %t423), !dbg !27
  %t425 = load i32, ptr %t366, !dbg !27
  %t426 = getelementptr inbounds { ptr, i32, i32, i32, i32 }, ptr %slot30, i32 0, i32 1, !dbg !27
  %t427 = load i32, ptr %t426, !dbg !27
  %t428 = icmp ugt i32 %t369, %t425, !dbg !27
  %t429 = icmp ugt i32 %t369, %t427, !dbg !27
  %t430 = sub i32 %t427, %t369, !dbg !27
  %t431 = icmp ult i32 %t430, 4, !dbg !27
  %t432 = or i1 %t428, %t429, !dbg !27
  %t433 = or i1 %t432, %t431, !dbg !27
  br i1 %t433, label %lua.raise.58, label %lua.ok.59, !prof !7, !dbg !27
lua.raise.58:
  %t434 = getelementptr inbounds ptr, ptr %t1, i64 11, !dbg !27
  %rt.raise.435 = load ptr, ptr %t434, !invariant.load !8, !dbg !27
  call void %rt.raise.435(ptr %L, i64 11) nomerge, !dbg !27
  unreachable, !dbg !27
lua.ok.59:
  %t436 = icmp ult i32 %t369, %t425, !dbg !27
  %t437 = sub i32 %t425, %t369, !dbg !27
  %t438 = icmp ult i32 %t437, 4, !dbg !27
  %t439 = and i1 %t436, %t438, !dbg !27
  br i1 %t439, label %lua.raise.60, label %lua.ok.61, !prof !7, !dbg !27
lua.raise.60:
  %t440 = getelementptr inbounds ptr, ptr %t1, i64 11, !dbg !27
  %rt.raise.441 = load ptr, ptr %t440, !invariant.load !8, !dbg !27
  call void %rt.raise.441(ptr %L, i64 12) nomerge, !dbg !27
  unreachable, !dbg !27
lua.ok.61:
  %t442 = icmp eq i32 %t369, %t425, !dbg !27
  %t443 = add i32 %t425, 4, !dbg !27
  %t444 = select i1 %t442, i32 %t443, i32 %t425, !dbg !27
  store i32 %t444, ptr %t366, !dbg !27
  %t445 = getelementptr inbounds { ptr, i32, i32, i32, i32 }, ptr %slot30, i32 0, i32 0, !dbg !27
  %t446 = load ptr, ptr %t445, !dbg !27
  %t447 = zext i32 %t369 to i64, !dbg !27
  %t448 = getelementptr inbounds i8, ptr %t446, i64 %t447, !dbg !27
  store i32 %t424, ptr %t448, align 1, !dbg !27
  %t449 = load i32, ptr %slot36, !dbg !28
  %t450 = call i32 @ks_encode_aot_helper_u32(double 0x4028000000000000), !dbg !28
  %t451 = call i32 @ks_encode_aot_helper_add(i32 %t449, i32 %t450), !dbg !28
  store i32 %t451, ptr %slot36, !dbg !28
  %t452 = load i32, ptr %slot38, !dbg !29
  %t453 = call i32 @ks_encode_aot_helper_u32(double 0x4030000000000000), !dbg !29
  %t454 = call i32 @ks_encode_aot_helper_add(i32 %t452, i32 %t453), !dbg !29
  store i32 %t454, ptr %slot38, !dbg !29
  br label %while.head.5, !dbg !29
while.end.7:
  br label %while.head.62, !dbg !30
while.head.62:
  %t455 = load i32, ptr %slot36, !dbg !30
  %t456 = call i32 @ks_encode_aot_helper_u32(double 0x4008000000000000), !dbg !30
  %t457 = call i32 @ks_encode_aot_helper_add(i32 %t455, i32 %t456), !dbg !30
  %t458 = load i32, ptr %slot13, !dbg !30
  %t459 = icmp ule i32 %t457, %t458, !dbg !30
  br i1 %t459, label %while.body.63, label %while.end.64, !dbg !30
while.body.63:
  %t460 = load i32, ptr %slot36, !dbg !31
  %t461 = zext i32 %t460 to i64, !dbg !31
  %t462 = icmp uge i64 %t461, %t8, !dbg !31
  br i1 %t462, label %lua.raise.65, label %lua.ok.66, !prof !7, !dbg !31
lua.raise.65:
  %t463 = getelementptr inbounds ptr, ptr %t1, i64 11, !dbg !31
  %rt.raise.464 = load ptr, ptr %t463, !invariant.load !8, !dbg !31
  call void %rt.raise.464(ptr %L, i64 3) nomerge, !dbg !31
  unreachable, !dbg !31
lua.ok.66:
  %t465 = getelementptr inbounds i8, ptr %t7, i64 %t461, !dbg !31
  %t466 = load i8, ptr %t465, !dbg !31
  %t467 = zext i8 %t466 to i32, !dbg !31
  store i32 %t467, ptr %slot468, !dbg !31
  %t469 = load i32, ptr %slot36, !dbg !32
  %t470 = call i32 @ks_encode_aot_helper_u32(double 0x3FF0000000000000), !dbg !32
  %t471 = call i32 @ks_encode_aot_helper_add(i32 %t469, i32 %t470), !dbg !32
  %t472 = zext i32 %t471 to i64, !dbg !32
  %t473 = icmp uge i64 %t472, %t8, !dbg !32
  br i1 %t473, label %lua.raise.67, label %lua.ok.68, !prof !7, !dbg !32
lua.raise.67:
  %t474 = getelementptr inbounds ptr, ptr %t1, i64 11, !dbg !32
  %rt.raise.475 = load ptr, ptr %t474, !invariant.load !8, !dbg !32
  call void %rt.raise.475(ptr %L, i64 3) nomerge, !dbg !32
  unreachable, !dbg !32
lua.ok.68:
  %t476 = getelementptr inbounds i8, ptr %t7, i64 %t472, !dbg !32
  %t477 = load i8, ptr %t476, !dbg !32
  %t478 = zext i8 %t477 to i32, !dbg !32
  store i32 %t478, ptr %slot479, !dbg !32
  %t480 = load i32, ptr %slot36, !dbg !33
  %t481 = call i32 @ks_encode_aot_helper_u32(double 0x4000000000000000), !dbg !33
  %t482 = call i32 @ks_encode_aot_helper_add(i32 %t480, i32 %t481), !dbg !33
  %t483 = zext i32 %t482 to i64, !dbg !33
  %t484 = icmp uge i64 %t483, %t8, !dbg !33
  br i1 %t484, label %lua.raise.69, label %lua.ok.70, !prof !7, !dbg !33
lua.raise.69:
  %t485 = getelementptr inbounds ptr, ptr %t1, i64 11, !dbg !33
  %rt.raise.486 = load ptr, ptr %t485, !invariant.load !8, !dbg !33
  call void %rt.raise.486(ptr %L, i64 3) nomerge, !dbg !33
  unreachable, !dbg !33
lua.ok.70:
  %t487 = getelementptr inbounds i8, ptr %t7, i64 %t483, !dbg !33
  %t488 = load i8, ptr %t487, !dbg !33
  %t489 = zext i8 %t488 to i32, !dbg !33
  store i32 %t489, ptr %slot490, !dbg !33
  %t491 = getelementptr inbounds { ptr, i32, i32, i32, i32 }, ptr %slot30, i32 0, i32 2, !dbg !34
  %t492 = load i32, ptr %slot38, !dbg !34
  %t493 = load i32, ptr %slot468, !dbg !34
  %t494 = call i32 @ks_encode_aot_helper_u32(double 0x4000000000000000), !dbg !34
  %t495 = call i32 @ks_encode_aot_helper_shr(i32 %t493, i32 %t494), !dbg !34
  %t496 = zext i32 %t495 to i64, !dbg !34
  %t497 = icmp uge i64 %t496, 64, !dbg !34
  br i1 %t497, label %lua.raise.71, label %lua.ok.72, !prof !7, !dbg !34
lua.raise.71:
  %t498 = getelementptr inbounds ptr, ptr %t1, i64 11, !dbg !34
  %rt.raise.499 = load ptr, ptr %t498, !invariant.load !8, !dbg !34
  call void %rt.raise.499(ptr %L, i64 3) nomerge, !dbg !34
  unreachable, !dbg !34
lua.ok.72:
  %t500 = getelementptr inbounds i8, ptr @nupp.bytes.1, i64 %t496, !dbg !34
  %t501 = load i8, ptr %t500, !dbg !34
  %t502 = zext i8 %t501 to i32, !dbg !34
  %t503 = load i32, ptr %t491, !dbg !34
  %t504 = getelementptr inbounds { ptr, i32, i32, i32, i32 }, ptr %slot30, i32 0, i32 1, !dbg !34
  %t505 = load i32, ptr %t504, !dbg !34
  %t506 = icmp ugt i32 %t492, %t503, !dbg !34
  %t507 = icmp uge i32 %t492, %t505, !dbg !34
  %t508 = or i1 %t506, %t507, !dbg !34
  %t509 = icmp ugt i32 %t502, 255, !dbg !34
  %t510 = or i1 %t508, %t509, !dbg !34
  br i1 %t510, label %lua.raise.73, label %lua.ok.74, !prof !7, !dbg !34
lua.raise.73:
  %t511 = getelementptr inbounds ptr, ptr %t1, i64 11, !dbg !34
  %rt.raise.512 = load ptr, ptr %t511, !invariant.load !8, !dbg !34
  call void %rt.raise.512(ptr %L, i64 11) nomerge, !dbg !34
  unreachable, !dbg !34
lua.ok.74:
  %t513 = icmp eq i32 %t492, %t503, !dbg !34
  %t514 = add i32 %t503, 1, !dbg !34
  %t515 = select i1 %t513, i32 %t514, i32 %t503, !dbg !34
  store i32 %t515, ptr %t491, !dbg !34
  %t516 = getelementptr inbounds { ptr, i32, i32, i32, i32 }, ptr %slot30, i32 0, i32 0, !dbg !34
  %t517 = load ptr, ptr %t516, !dbg !34
  %t518 = zext i32 %t492 to i64, !dbg !34
  %t519 = getelementptr inbounds i8, ptr %t517, i64 %t518, !dbg !34
  %t520 = trunc i32 %t502 to i8, !dbg !34
  store i8 %t520, ptr %t519, !dbg !34
  %t521 = getelementptr inbounds { ptr, i32, i32, i32, i32 }, ptr %slot30, i32 0, i32 2, !dbg !35
  %t522 = load i32, ptr %slot38, !dbg !35
  %t523 = call i32 @ks_encode_aot_helper_u32(double 0x3FF0000000000000), !dbg !35
  %t524 = call i32 @ks_encode_aot_helper_add(i32 %t522, i32 %t523), !dbg !35
  %t525 = load i32, ptr %slot468, !dbg !35
  %t526 = call i32 @ks_encode_aot_helper_u32(double 0x4008000000000000), !dbg !35
  %t527 = call i32 @ks_encode_aot_helper_and_bits(i32 %t525, i32 %t526), !dbg !35
  %t528 = call i32 @ks_encode_aot_helper_u32(double 0x4010000000000000), !dbg !35
  %t529 = call i32 @ks_encode_aot_helper_shl(i32 %t527, i32 %t528), !dbg !35
  %t530 = load i32, ptr %slot479, !dbg !35
  %t531 = call i32 @ks_encode_aot_helper_u32(double 0x4010000000000000), !dbg !35
  %t532 = call i32 @ks_encode_aot_helper_shr(i32 %t530, i32 %t531), !dbg !35
  %t533 = call i32 @ks_encode_aot_helper_or_bits(i32 %t529, i32 %t532), !dbg !35
  %t534 = zext i32 %t533 to i64, !dbg !35
  %t535 = icmp uge i64 %t534, 64, !dbg !35
  br i1 %t535, label %lua.raise.75, label %lua.ok.76, !prof !7, !dbg !35
lua.raise.75:
  %t536 = getelementptr inbounds ptr, ptr %t1, i64 11, !dbg !35
  %rt.raise.537 = load ptr, ptr %t536, !invariant.load !8, !dbg !35
  call void %rt.raise.537(ptr %L, i64 3) nomerge, !dbg !35
  unreachable, !dbg !35
lua.ok.76:
  %t538 = getelementptr inbounds i8, ptr @nupp.bytes.1, i64 %t534, !dbg !35
  %t539 = load i8, ptr %t538, !dbg !35
  %t540 = zext i8 %t539 to i32, !dbg !35
  %t541 = load i32, ptr %t521, !dbg !35
  %t542 = getelementptr inbounds { ptr, i32, i32, i32, i32 }, ptr %slot30, i32 0, i32 1, !dbg !35
  %t543 = load i32, ptr %t542, !dbg !35
  %t544 = icmp ugt i32 %t524, %t541, !dbg !35
  %t545 = icmp uge i32 %t524, %t543, !dbg !35
  %t546 = or i1 %t544, %t545, !dbg !35
  %t547 = icmp ugt i32 %t540, 255, !dbg !35
  %t548 = or i1 %t546, %t547, !dbg !35
  br i1 %t548, label %lua.raise.77, label %lua.ok.78, !prof !7, !dbg !35
lua.raise.77:
  %t549 = getelementptr inbounds ptr, ptr %t1, i64 11, !dbg !35
  %rt.raise.550 = load ptr, ptr %t549, !invariant.load !8, !dbg !35
  call void %rt.raise.550(ptr %L, i64 11) nomerge, !dbg !35
  unreachable, !dbg !35
lua.ok.78:
  %t551 = icmp eq i32 %t524, %t541, !dbg !35
  %t552 = add i32 %t541, 1, !dbg !35
  %t553 = select i1 %t551, i32 %t552, i32 %t541, !dbg !35
  store i32 %t553, ptr %t521, !dbg !35
  %t554 = getelementptr inbounds { ptr, i32, i32, i32, i32 }, ptr %slot30, i32 0, i32 0, !dbg !35
  %t555 = load ptr, ptr %t554, !dbg !35
  %t556 = zext i32 %t524 to i64, !dbg !35
  %t557 = getelementptr inbounds i8, ptr %t555, i64 %t556, !dbg !35
  %t558 = trunc i32 %t540 to i8, !dbg !35
  store i8 %t558, ptr %t557, !dbg !35
  %t559 = getelementptr inbounds { ptr, i32, i32, i32, i32 }, ptr %slot30, i32 0, i32 2, !dbg !36
  %t560 = load i32, ptr %slot38, !dbg !36
  %t561 = call i32 @ks_encode_aot_helper_u32(double 0x4000000000000000), !dbg !36
  %t562 = call i32 @ks_encode_aot_helper_add(i32 %t560, i32 %t561), !dbg !36
  %t563 = load i32, ptr %slot479, !dbg !36
  %t564 = call i32 @ks_encode_aot_helper_u32(double 0x402E000000000000), !dbg !36
  %t565 = call i32 @ks_encode_aot_helper_and_bits(i32 %t563, i32 %t564), !dbg !36
  %t566 = call i32 @ks_encode_aot_helper_u32(double 0x4000000000000000), !dbg !36
  %t567 = call i32 @ks_encode_aot_helper_shl(i32 %t565, i32 %t566), !dbg !36
  %t568 = load i32, ptr %slot490, !dbg !36
  %t569 = call i32 @ks_encode_aot_helper_u32(double 0x4018000000000000), !dbg !36
  %t570 = call i32 @ks_encode_aot_helper_shr(i32 %t568, i32 %t569), !dbg !36
  %t571 = call i32 @ks_encode_aot_helper_or_bits(i32 %t567, i32 %t570), !dbg !36
  %t572 = zext i32 %t571 to i64, !dbg !36
  %t573 = icmp uge i64 %t572, 64, !dbg !36
  br i1 %t573, label %lua.raise.79, label %lua.ok.80, !prof !7, !dbg !36
lua.raise.79:
  %t574 = getelementptr inbounds ptr, ptr %t1, i64 11, !dbg !36
  %rt.raise.575 = load ptr, ptr %t574, !invariant.load !8, !dbg !36
  call void %rt.raise.575(ptr %L, i64 3) nomerge, !dbg !36
  unreachable, !dbg !36
lua.ok.80:
  %t576 = getelementptr inbounds i8, ptr @nupp.bytes.1, i64 %t572, !dbg !36
  %t577 = load i8, ptr %t576, !dbg !36
  %t578 = zext i8 %t577 to i32, !dbg !36
  %t579 = load i32, ptr %t559, !dbg !36
  %t580 = getelementptr inbounds { ptr, i32, i32, i32, i32 }, ptr %slot30, i32 0, i32 1, !dbg !36
  %t581 = load i32, ptr %t580, !dbg !36
  %t582 = icmp ugt i32 %t562, %t579, !dbg !36
  %t583 = icmp uge i32 %t562, %t581, !dbg !36
  %t584 = or i1 %t582, %t583, !dbg !36
  %t585 = icmp ugt i32 %t578, 255, !dbg !36
  %t586 = or i1 %t584, %t585, !dbg !36
  br i1 %t586, label %lua.raise.81, label %lua.ok.82, !prof !7, !dbg !36
lua.raise.81:
  %t587 = getelementptr inbounds ptr, ptr %t1, i64 11, !dbg !36
  %rt.raise.588 = load ptr, ptr %t587, !invariant.load !8, !dbg !36
  call void %rt.raise.588(ptr %L, i64 11) nomerge, !dbg !36
  unreachable, !dbg !36
lua.ok.82:
  %t589 = icmp eq i32 %t562, %t579, !dbg !36
  %t590 = add i32 %t579, 1, !dbg !36
  %t591 = select i1 %t589, i32 %t590, i32 %t579, !dbg !36
  store i32 %t591, ptr %t559, !dbg !36
  %t592 = getelementptr inbounds { ptr, i32, i32, i32, i32 }, ptr %slot30, i32 0, i32 0, !dbg !36
  %t593 = load ptr, ptr %t592, !dbg !36
  %t594 = zext i32 %t562 to i64, !dbg !36
  %t595 = getelementptr inbounds i8, ptr %t593, i64 %t594, !dbg !36
  %t596 = trunc i32 %t578 to i8, !dbg !36
  store i8 %t596, ptr %t595, !dbg !36
  %t597 = getelementptr inbounds { ptr, i32, i32, i32, i32 }, ptr %slot30, i32 0, i32 2, !dbg !37
  %t598 = load i32, ptr %slot38, !dbg !37
  %t599 = call i32 @ks_encode_aot_helper_u32(double 0x4008000000000000), !dbg !37
  %t600 = call i32 @ks_encode_aot_helper_add(i32 %t598, i32 %t599), !dbg !37
  %t601 = load i32, ptr %slot490, !dbg !37
  %t602 = call i32 @ks_encode_aot_helper_u32(double 0x404F800000000000), !dbg !37
  %t603 = call i32 @ks_encode_aot_helper_and_bits(i32 %t601, i32 %t602), !dbg !37
  %t604 = zext i32 %t603 to i64, !dbg !37
  %t605 = icmp uge i64 %t604, 64, !dbg !37
  br i1 %t605, label %lua.raise.83, label %lua.ok.84, !prof !7, !dbg !37
lua.raise.83:
  %t606 = getelementptr inbounds ptr, ptr %t1, i64 11, !dbg !37
  %rt.raise.607 = load ptr, ptr %t606, !invariant.load !8, !dbg !37
  call void %rt.raise.607(ptr %L, i64 3) nomerge, !dbg !37
  unreachable, !dbg !37
lua.ok.84:
  %t608 = getelementptr inbounds i8, ptr @nupp.bytes.1, i64 %t604, !dbg !37
  %t609 = load i8, ptr %t608, !dbg !37
  %t610 = zext i8 %t609 to i32, !dbg !37
  %t611 = load i32, ptr %t597, !dbg !37
  %t612 = getelementptr inbounds { ptr, i32, i32, i32, i32 }, ptr %slot30, i32 0, i32 1, !dbg !37
  %t613 = load i32, ptr %t612, !dbg !37
  %t614 = icmp ugt i32 %t600, %t611, !dbg !37
  %t615 = icmp uge i32 %t600, %t613, !dbg !37
  %t616 = or i1 %t614, %t615, !dbg !37
  %t617 = icmp ugt i32 %t610, 255, !dbg !37
  %t618 = or i1 %t616, %t617, !dbg !37
  br i1 %t618, label %lua.raise.85, label %lua.ok.86, !prof !7, !dbg !37
lua.raise.85:
  %t619 = getelementptr inbounds ptr, ptr %t1, i64 11, !dbg !37
  %rt.raise.620 = load ptr, ptr %t619, !invariant.load !8, !dbg !37
  call void %rt.raise.620(ptr %L, i64 11) nomerge, !dbg !37
  unreachable, !dbg !37
lua.ok.86:
  %t621 = icmp eq i32 %t600, %t611, !dbg !37
  %t622 = add i32 %t611, 1, !dbg !37
  %t623 = select i1 %t621, i32 %t622, i32 %t611, !dbg !37
  store i32 %t623, ptr %t597, !dbg !37
  %t624 = getelementptr inbounds { ptr, i32, i32, i32, i32 }, ptr %slot30, i32 0, i32 0, !dbg !37
  %t625 = load ptr, ptr %t624, !dbg !37
  %t626 = zext i32 %t600 to i64, !dbg !37
  %t627 = getelementptr inbounds i8, ptr %t625, i64 %t626, !dbg !37
  %t628 = trunc i32 %t610 to i8, !dbg !37
  store i8 %t628, ptr %t627, !dbg !37
  %t629 = load i32, ptr %slot36, !dbg !38
  %t630 = call i32 @ks_encode_aot_helper_u32(double 0x4008000000000000), !dbg !38
  %t631 = call i32 @ks_encode_aot_helper_add(i32 %t629, i32 %t630), !dbg !38
  store i32 %t631, ptr %slot36, !dbg !38
  %t632 = load i32, ptr %slot38, !dbg !39
  %t633 = call i32 @ks_encode_aot_helper_u32(double 0x4010000000000000), !dbg !39
  %t634 = call i32 @ks_encode_aot_helper_add(i32 %t632, i32 %t633), !dbg !39
  store i32 %t634, ptr %slot38, !dbg !39
  br label %while.head.62, !dbg !39
while.end.64:
  %t635 = load i32, ptr %slot13, !dbg !40
  %t636 = load i32, ptr %slot36, !dbg !40
  %t637 = sub i32 %t635, %t636, !dbg !40
  store i32 %t637, ptr %slot638, !dbg !40
  %t639 = load i32, ptr %slot638, !dbg !41
  %t640 = icmp eq i32 %t639, 1, !dbg !41
  br i1 %t640, label %if.then.88, label %if.else.89, !dbg !41
if.then.88:
  %t641 = load i32, ptr %slot36, !dbg !42
  %t642 = zext i32 %t641 to i64, !dbg !42
  %t643 = icmp uge i64 %t642, %t8, !dbg !42
  br i1 %t643, label %lua.raise.90, label %lua.ok.91, !prof !7, !dbg !42
lua.raise.90:
  %t644 = getelementptr inbounds ptr, ptr %t1, i64 11, !dbg !42
  %rt.raise.645 = load ptr, ptr %t644, !invariant.load !8, !dbg !42
  call void %rt.raise.645(ptr %L, i64 3) nomerge, !dbg !42
  unreachable, !dbg !42
lua.ok.91:
  %t646 = getelementptr inbounds i8, ptr %t7, i64 %t642, !dbg !42
  %t647 = load i8, ptr %t646, !dbg !42
  %t648 = zext i8 %t647 to i32, !dbg !42
  store i32 %t648, ptr %slot649, !dbg !42
  %t650 = getelementptr inbounds { ptr, i32, i32, i32, i32 }, ptr %slot30, i32 0, i32 2, !dbg !43
  %t651 = load i32, ptr %slot38, !dbg !43
  %t652 = load i32, ptr %slot649, !dbg !43
  %t653 = call i32 @ks_encode_aot_helper_u32(double 0x4000000000000000), !dbg !43
  %t654 = call i32 @ks_encode_aot_helper_shr(i32 %t652, i32 %t653), !dbg !43
  %t655 = zext i32 %t654 to i64, !dbg !43
  %t656 = icmp uge i64 %t655, 64, !dbg !43
  br i1 %t656, label %lua.raise.92, label %lua.ok.93, !prof !7, !dbg !43
lua.raise.92:
  %t657 = getelementptr inbounds ptr, ptr %t1, i64 11, !dbg !43
  %rt.raise.658 = load ptr, ptr %t657, !invariant.load !8, !dbg !43
  call void %rt.raise.658(ptr %L, i64 3) nomerge, !dbg !43
  unreachable, !dbg !43
lua.ok.93:
  %t659 = getelementptr inbounds i8, ptr @nupp.bytes.1, i64 %t655, !dbg !43
  %t660 = load i8, ptr %t659, !dbg !43
  %t661 = zext i8 %t660 to i32, !dbg !43
  %t662 = load i32, ptr %t650, !dbg !43
  %t663 = getelementptr inbounds { ptr, i32, i32, i32, i32 }, ptr %slot30, i32 0, i32 1, !dbg !43
  %t664 = load i32, ptr %t663, !dbg !43
  %t665 = icmp ugt i32 %t651, %t662, !dbg !43
  %t666 = icmp uge i32 %t651, %t664, !dbg !43
  %t667 = or i1 %t665, %t666, !dbg !43
  %t668 = icmp ugt i32 %t661, 255, !dbg !43
  %t669 = or i1 %t667, %t668, !dbg !43
  br i1 %t669, label %lua.raise.94, label %lua.ok.95, !prof !7, !dbg !43
lua.raise.94:
  %t670 = getelementptr inbounds ptr, ptr %t1, i64 11, !dbg !43
  %rt.raise.671 = load ptr, ptr %t670, !invariant.load !8, !dbg !43
  call void %rt.raise.671(ptr %L, i64 11) nomerge, !dbg !43
  unreachable, !dbg !43
lua.ok.95:
  %t672 = icmp eq i32 %t651, %t662, !dbg !43
  %t673 = add i32 %t662, 1, !dbg !43
  %t674 = select i1 %t672, i32 %t673, i32 %t662, !dbg !43
  store i32 %t674, ptr %t650, !dbg !43
  %t675 = getelementptr inbounds { ptr, i32, i32, i32, i32 }, ptr %slot30, i32 0, i32 0, !dbg !43
  %t676 = load ptr, ptr %t675, !dbg !43
  %t677 = zext i32 %t651 to i64, !dbg !43
  %t678 = getelementptr inbounds i8, ptr %t676, i64 %t677, !dbg !43
  %t679 = trunc i32 %t661 to i8, !dbg !43
  store i8 %t679, ptr %t678, !dbg !43
  %t680 = getelementptr inbounds { ptr, i32, i32, i32, i32 }, ptr %slot30, i32 0, i32 2, !dbg !44
  %t681 = load i32, ptr %slot38, !dbg !44
  %t682 = call i32 @ks_encode_aot_helper_u32(double 0x3FF0000000000000), !dbg !44
  %t683 = call i32 @ks_encode_aot_helper_add(i32 %t681, i32 %t682), !dbg !44
  %t684 = load i32, ptr %slot649, !dbg !44
  %t685 = call i32 @ks_encode_aot_helper_u32(double 0x4008000000000000), !dbg !44
  %t686 = call i32 @ks_encode_aot_helper_and_bits(i32 %t684, i32 %t685), !dbg !44
  %t687 = call i32 @ks_encode_aot_helper_u32(double 0x4010000000000000), !dbg !44
  %t688 = call i32 @ks_encode_aot_helper_shl(i32 %t686, i32 %t687), !dbg !44
  %t689 = zext i32 %t688 to i64, !dbg !44
  %t690 = icmp uge i64 %t689, 64, !dbg !44
  br i1 %t690, label %lua.raise.96, label %lua.ok.97, !prof !7, !dbg !44
lua.raise.96:
  %t691 = getelementptr inbounds ptr, ptr %t1, i64 11, !dbg !44
  %rt.raise.692 = load ptr, ptr %t691, !invariant.load !8, !dbg !44
  call void %rt.raise.692(ptr %L, i64 3) nomerge, !dbg !44
  unreachable, !dbg !44
lua.ok.97:
  %t693 = getelementptr inbounds i8, ptr @nupp.bytes.1, i64 %t689, !dbg !44
  %t694 = load i8, ptr %t693, !dbg !44
  %t695 = zext i8 %t694 to i32, !dbg !44
  %t696 = load i32, ptr %t680, !dbg !44
  %t697 = getelementptr inbounds { ptr, i32, i32, i32, i32 }, ptr %slot30, i32 0, i32 1, !dbg !44
  %t698 = load i32, ptr %t697, !dbg !44
  %t699 = icmp ugt i32 %t683, %t696, !dbg !44
  %t700 = icmp uge i32 %t683, %t698, !dbg !44
  %t701 = or i1 %t699, %t700, !dbg !44
  %t702 = icmp ugt i32 %t695, 255, !dbg !44
  %t703 = or i1 %t701, %t702, !dbg !44
  br i1 %t703, label %lua.raise.98, label %lua.ok.99, !prof !7, !dbg !44
lua.raise.98:
  %t704 = getelementptr inbounds ptr, ptr %t1, i64 11, !dbg !44
  %rt.raise.705 = load ptr, ptr %t704, !invariant.load !8, !dbg !44
  call void %rt.raise.705(ptr %L, i64 11) nomerge, !dbg !44
  unreachable, !dbg !44
lua.ok.99:
  %t706 = icmp eq i32 %t683, %t696, !dbg !44
  %t707 = add i32 %t696, 1, !dbg !44
  %t708 = select i1 %t706, i32 %t707, i32 %t696, !dbg !44
  store i32 %t708, ptr %t680, !dbg !44
  %t709 = getelementptr inbounds { ptr, i32, i32, i32, i32 }, ptr %slot30, i32 0, i32 0, !dbg !44
  %t710 = load ptr, ptr %t709, !dbg !44
  %t711 = zext i32 %t683 to i64, !dbg !44
  %t712 = getelementptr inbounds i8, ptr %t710, i64 %t711, !dbg !44
  %t713 = trunc i32 %t695 to i8, !dbg !44
  store i8 %t713, ptr %t712, !dbg !44
  %t714 = getelementptr inbounds { ptr, i32, i32, i32, i32 }, ptr %slot30, i32 0, i32 2, !dbg !45
  %t715 = load i32, ptr %slot38, !dbg !45
  %t716 = call i32 @ks_encode_aot_helper_u32(double 0x4000000000000000), !dbg !45
  %t717 = call i32 @ks_encode_aot_helper_add(i32 %t715, i32 %t716), !dbg !45
  %t718 = call i32 @ks_encode_aot_helper_u32(double 0x404E800000000000), !dbg !45
  %t719 = load i32, ptr %t714, !dbg !45
  %t720 = getelementptr inbounds { ptr, i32, i32, i32, i32 }, ptr %slot30, i32 0, i32 1, !dbg !45
  %t721 = load i32, ptr %t720, !dbg !45
  %t722 = icmp ugt i32 %t717, %t719, !dbg !45
  %t723 = icmp uge i32 %t717, %t721, !dbg !45
  %t724 = or i1 %t722, %t723, !dbg !45
  %t725 = icmp ugt i32 %t718, 255, !dbg !45
  %t726 = or i1 %t724, %t725, !dbg !45
  br i1 %t726, label %lua.raise.100, label %lua.ok.101, !prof !7, !dbg !45
lua.raise.100:
  %t727 = getelementptr inbounds ptr, ptr %t1, i64 11, !dbg !45
  %rt.raise.728 = load ptr, ptr %t727, !invariant.load !8, !dbg !45
  call void %rt.raise.728(ptr %L, i64 11) nomerge, !dbg !45
  unreachable, !dbg !45
lua.ok.101:
  %t729 = icmp eq i32 %t717, %t719, !dbg !45
  %t730 = add i32 %t719, 1, !dbg !45
  %t731 = select i1 %t729, i32 %t730, i32 %t719, !dbg !45
  store i32 %t731, ptr %t714, !dbg !45
  %t732 = getelementptr inbounds { ptr, i32, i32, i32, i32 }, ptr %slot30, i32 0, i32 0, !dbg !45
  %t733 = load ptr, ptr %t732, !dbg !45
  %t734 = zext i32 %t717 to i64, !dbg !45
  %t735 = getelementptr inbounds i8, ptr %t733, i64 %t734, !dbg !45
  %t736 = trunc i32 %t718 to i8, !dbg !45
  store i8 %t736, ptr %t735, !dbg !45
  %t737 = getelementptr inbounds { ptr, i32, i32, i32, i32 }, ptr %slot30, i32 0, i32 2, !dbg !46
  %t738 = load i32, ptr %slot38, !dbg !46
  %t739 = call i32 @ks_encode_aot_helper_u32(double 0x4008000000000000), !dbg !46
  %t740 = call i32 @ks_encode_aot_helper_add(i32 %t738, i32 %t739), !dbg !46
  %t741 = call i32 @ks_encode_aot_helper_u32(double 0x404E800000000000), !dbg !46
  %t742 = load i32, ptr %t737, !dbg !46
  %t743 = getelementptr inbounds { ptr, i32, i32, i32, i32 }, ptr %slot30, i32 0, i32 1, !dbg !46
  %t744 = load i32, ptr %t743, !dbg !46
  %t745 = icmp ugt i32 %t740, %t742, !dbg !46
  %t746 = icmp uge i32 %t740, %t744, !dbg !46
  %t747 = or i1 %t745, %t746, !dbg !46
  %t748 = icmp ugt i32 %t741, 255, !dbg !46
  %t749 = or i1 %t747, %t748, !dbg !46
  br i1 %t749, label %lua.raise.102, label %lua.ok.103, !prof !7, !dbg !46
lua.raise.102:
  %t750 = getelementptr inbounds ptr, ptr %t1, i64 11, !dbg !46
  %rt.raise.751 = load ptr, ptr %t750, !invariant.load !8, !dbg !46
  call void %rt.raise.751(ptr %L, i64 11) nomerge, !dbg !46
  unreachable, !dbg !46
lua.ok.103:
  %t752 = icmp eq i32 %t740, %t742, !dbg !46
  %t753 = add i32 %t742, 1, !dbg !46
  %t754 = select i1 %t752, i32 %t753, i32 %t742, !dbg !46
  store i32 %t754, ptr %t737, !dbg !46
  %t755 = getelementptr inbounds { ptr, i32, i32, i32, i32 }, ptr %slot30, i32 0, i32 0, !dbg !46
  %t756 = load ptr, ptr %t755, !dbg !46
  %t757 = zext i32 %t740 to i64, !dbg !46
  %t758 = getelementptr inbounds i8, ptr %t756, i64 %t757, !dbg !46
  %t759 = trunc i32 %t741 to i8, !dbg !46
  store i8 %t759, ptr %t758, !dbg !46
  %t760 = load i32, ptr %slot38, !dbg !47
  %t761 = call i32 @ks_encode_aot_helper_u32(double 0x4010000000000000), !dbg !47
  %t762 = call i32 @ks_encode_aot_helper_add(i32 %t760, i32 %t761), !dbg !47
  store i32 %t762, ptr %slot38, !dbg !47
  br label %if.end.87, !dbg !47
if.else.89:
  %t763 = load i32, ptr %slot638, !dbg !47
  %t764 = icmp eq i32 %t763, 2, !dbg !47
  br i1 %t764, label %if.then.104, label %if.else.105, !dbg !47
if.then.104:
  %t765 = load i32, ptr %slot36, !dbg !48
  %t766 = zext i32 %t765 to i64, !dbg !48
  %t767 = icmp uge i64 %t766, %t8, !dbg !48
  br i1 %t767, label %lua.raise.106, label %lua.ok.107, !prof !7, !dbg !48
lua.raise.106:
  %t768 = getelementptr inbounds ptr, ptr %t1, i64 11, !dbg !48
  %rt.raise.769 = load ptr, ptr %t768, !invariant.load !8, !dbg !48
  call void %rt.raise.769(ptr %L, i64 3) nomerge, !dbg !48
  unreachable, !dbg !48
lua.ok.107:
  %t770 = getelementptr inbounds i8, ptr %t7, i64 %t766, !dbg !48
  %t771 = load i8, ptr %t770, !dbg !48
  %t772 = zext i8 %t771 to i32, !dbg !48
  store i32 %t772, ptr %slot773, !dbg !48
  %t774 = load i32, ptr %slot36, !dbg !49
  %t775 = call i32 @ks_encode_aot_helper_u32(double 0x3FF0000000000000), !dbg !49
  %t776 = call i32 @ks_encode_aot_helper_add(i32 %t774, i32 %t775), !dbg !49
  %t777 = zext i32 %t776 to i64, !dbg !49
  %t778 = icmp uge i64 %t777, %t8, !dbg !49
  br i1 %t778, label %lua.raise.108, label %lua.ok.109, !prof !7, !dbg !49
lua.raise.108:
  %t779 = getelementptr inbounds ptr, ptr %t1, i64 11, !dbg !49
  %rt.raise.780 = load ptr, ptr %t779, !invariant.load !8, !dbg !49
  call void %rt.raise.780(ptr %L, i64 3) nomerge, !dbg !49
  unreachable, !dbg !49
lua.ok.109:
  %t781 = getelementptr inbounds i8, ptr %t7, i64 %t777, !dbg !49
  %t782 = load i8, ptr %t781, !dbg !49
  %t783 = zext i8 %t782 to i32, !dbg !49
  store i32 %t783, ptr %slot784, !dbg !49
  %t785 = getelementptr inbounds { ptr, i32, i32, i32, i32 }, ptr %slot30, i32 0, i32 2, !dbg !50
  %t786 = load i32, ptr %slot38, !dbg !50
  %t787 = load i32, ptr %slot773, !dbg !50
  %t788 = call i32 @ks_encode_aot_helper_u32(double 0x4000000000000000), !dbg !50
  %t789 = call i32 @ks_encode_aot_helper_shr(i32 %t787, i32 %t788), !dbg !50
  %t790 = zext i32 %t789 to i64, !dbg !50
  %t791 = icmp uge i64 %t790, 64, !dbg !50
  br i1 %t791, label %lua.raise.110, label %lua.ok.111, !prof !7, !dbg !50
lua.raise.110:
  %t792 = getelementptr inbounds ptr, ptr %t1, i64 11, !dbg !50
  %rt.raise.793 = load ptr, ptr %t792, !invariant.load !8, !dbg !50
  call void %rt.raise.793(ptr %L, i64 3) nomerge, !dbg !50
  unreachable, !dbg !50
lua.ok.111:
  %t794 = getelementptr inbounds i8, ptr @nupp.bytes.1, i64 %t790, !dbg !50
  %t795 = load i8, ptr %t794, !dbg !50
  %t796 = zext i8 %t795 to i32, !dbg !50
  %t797 = load i32, ptr %t785, !dbg !50
  %t798 = getelementptr inbounds { ptr, i32, i32, i32, i32 }, ptr %slot30, i32 0, i32 1, !dbg !50
  %t799 = load i32, ptr %t798, !dbg !50
  %t800 = icmp ugt i32 %t786, %t797, !dbg !50
  %t801 = icmp uge i32 %t786, %t799, !dbg !50
  %t802 = or i1 %t800, %t801, !dbg !50
  %t803 = icmp ugt i32 %t796, 255, !dbg !50
  %t804 = or i1 %t802, %t803, !dbg !50
  br i1 %t804, label %lua.raise.112, label %lua.ok.113, !prof !7, !dbg !50
lua.raise.112:
  %t805 = getelementptr inbounds ptr, ptr %t1, i64 11, !dbg !50
  %rt.raise.806 = load ptr, ptr %t805, !invariant.load !8, !dbg !50
  call void %rt.raise.806(ptr %L, i64 11) nomerge, !dbg !50
  unreachable, !dbg !50
lua.ok.113:
  %t807 = icmp eq i32 %t786, %t797, !dbg !50
  %t808 = add i32 %t797, 1, !dbg !50
  %t809 = select i1 %t807, i32 %t808, i32 %t797, !dbg !50
  store i32 %t809, ptr %t785, !dbg !50
  %t810 = getelementptr inbounds { ptr, i32, i32, i32, i32 }, ptr %slot30, i32 0, i32 0, !dbg !50
  %t811 = load ptr, ptr %t810, !dbg !50
  %t812 = zext i32 %t786 to i64, !dbg !50
  %t813 = getelementptr inbounds i8, ptr %t811, i64 %t812, !dbg !50
  %t814 = trunc i32 %t796 to i8, !dbg !50
  store i8 %t814, ptr %t813, !dbg !50
  %t815 = getelementptr inbounds { ptr, i32, i32, i32, i32 }, ptr %slot30, i32 0, i32 2, !dbg !51
  %t816 = load i32, ptr %slot38, !dbg !51
  %t817 = call i32 @ks_encode_aot_helper_u32(double 0x3FF0000000000000), !dbg !51
  %t818 = call i32 @ks_encode_aot_helper_add(i32 %t816, i32 %t817), !dbg !51
  %t819 = load i32, ptr %slot773, !dbg !51
  %t820 = call i32 @ks_encode_aot_helper_u32(double 0x4008000000000000), !dbg !51
  %t821 = call i32 @ks_encode_aot_helper_and_bits(i32 %t819, i32 %t820), !dbg !51
  %t822 = call i32 @ks_encode_aot_helper_u32(double 0x4010000000000000), !dbg !51
  %t823 = call i32 @ks_encode_aot_helper_shl(i32 %t821, i32 %t822), !dbg !51
  %t824 = load i32, ptr %slot784, !dbg !51
  %t825 = call i32 @ks_encode_aot_helper_u32(double 0x4010000000000000), !dbg !51
  %t826 = call i32 @ks_encode_aot_helper_shr(i32 %t824, i32 %t825), !dbg !51
  %t827 = call i32 @ks_encode_aot_helper_or_bits(i32 %t823, i32 %t826), !dbg !51
  %t828 = zext i32 %t827 to i64, !dbg !51
  %t829 = icmp uge i64 %t828, 64, !dbg !51
  br i1 %t829, label %lua.raise.114, label %lua.ok.115, !prof !7, !dbg !51
lua.raise.114:
  %t830 = getelementptr inbounds ptr, ptr %t1, i64 11, !dbg !51
  %rt.raise.831 = load ptr, ptr %t830, !invariant.load !8, !dbg !51
  call void %rt.raise.831(ptr %L, i64 3) nomerge, !dbg !51
  unreachable, !dbg !51
lua.ok.115:
  %t832 = getelementptr inbounds i8, ptr @nupp.bytes.1, i64 %t828, !dbg !51
  %t833 = load i8, ptr %t832, !dbg !51
  %t834 = zext i8 %t833 to i32, !dbg !51
  %t835 = load i32, ptr %t815, !dbg !51
  %t836 = getelementptr inbounds { ptr, i32, i32, i32, i32 }, ptr %slot30, i32 0, i32 1, !dbg !51
  %t837 = load i32, ptr %t836, !dbg !51
  %t838 = icmp ugt i32 %t818, %t835, !dbg !51
  %t839 = icmp uge i32 %t818, %t837, !dbg !51
  %t840 = or i1 %t838, %t839, !dbg !51
  %t841 = icmp ugt i32 %t834, 255, !dbg !51
  %t842 = or i1 %t840, %t841, !dbg !51
  br i1 %t842, label %lua.raise.116, label %lua.ok.117, !prof !7, !dbg !51
lua.raise.116:
  %t843 = getelementptr inbounds ptr, ptr %t1, i64 11, !dbg !51
  %rt.raise.844 = load ptr, ptr %t843, !invariant.load !8, !dbg !51
  call void %rt.raise.844(ptr %L, i64 11) nomerge, !dbg !51
  unreachable, !dbg !51
lua.ok.117:
  %t845 = icmp eq i32 %t818, %t835, !dbg !51
  %t846 = add i32 %t835, 1, !dbg !51
  %t847 = select i1 %t845, i32 %t846, i32 %t835, !dbg !51
  store i32 %t847, ptr %t815, !dbg !51
  %t848 = getelementptr inbounds { ptr, i32, i32, i32, i32 }, ptr %slot30, i32 0, i32 0, !dbg !51
  %t849 = load ptr, ptr %t848, !dbg !51
  %t850 = zext i32 %t818 to i64, !dbg !51
  %t851 = getelementptr inbounds i8, ptr %t849, i64 %t850, !dbg !51
  %t852 = trunc i32 %t834 to i8, !dbg !51
  store i8 %t852, ptr %t851, !dbg !51
  %t853 = getelementptr inbounds { ptr, i32, i32, i32, i32 }, ptr %slot30, i32 0, i32 2, !dbg !52
  %t854 = load i32, ptr %slot38, !dbg !52
  %t855 = call i32 @ks_encode_aot_helper_u32(double 0x4000000000000000), !dbg !52
  %t856 = call i32 @ks_encode_aot_helper_add(i32 %t854, i32 %t855), !dbg !52
  %t857 = load i32, ptr %slot784, !dbg !52
  %t858 = call i32 @ks_encode_aot_helper_u32(double 0x402E000000000000), !dbg !52
  %t859 = call i32 @ks_encode_aot_helper_and_bits(i32 %t857, i32 %t858), !dbg !52
  %t860 = call i32 @ks_encode_aot_helper_u32(double 0x4000000000000000), !dbg !52
  %t861 = call i32 @ks_encode_aot_helper_shl(i32 %t859, i32 %t860), !dbg !52
  %t862 = zext i32 %t861 to i64, !dbg !52
  %t863 = icmp uge i64 %t862, 64, !dbg !52
  br i1 %t863, label %lua.raise.118, label %lua.ok.119, !prof !7, !dbg !52
lua.raise.118:
  %t864 = getelementptr inbounds ptr, ptr %t1, i64 11, !dbg !52
  %rt.raise.865 = load ptr, ptr %t864, !invariant.load !8, !dbg !52
  call void %rt.raise.865(ptr %L, i64 3) nomerge, !dbg !52
  unreachable, !dbg !52
lua.ok.119:
  %t866 = getelementptr inbounds i8, ptr @nupp.bytes.1, i64 %t862, !dbg !52
  %t867 = load i8, ptr %t866, !dbg !52
  %t868 = zext i8 %t867 to i32, !dbg !52
  %t869 = load i32, ptr %t853, !dbg !52
  %t870 = getelementptr inbounds { ptr, i32, i32, i32, i32 }, ptr %slot30, i32 0, i32 1, !dbg !52
  %t871 = load i32, ptr %t870, !dbg !52
  %t872 = icmp ugt i32 %t856, %t869, !dbg !52
  %t873 = icmp uge i32 %t856, %t871, !dbg !52
  %t874 = or i1 %t872, %t873, !dbg !52
  %t875 = icmp ugt i32 %t868, 255, !dbg !52
  %t876 = or i1 %t874, %t875, !dbg !52
  br i1 %t876, label %lua.raise.120, label %lua.ok.121, !prof !7, !dbg !52
lua.raise.120:
  %t877 = getelementptr inbounds ptr, ptr %t1, i64 11, !dbg !52
  %rt.raise.878 = load ptr, ptr %t877, !invariant.load !8, !dbg !52
  call void %rt.raise.878(ptr %L, i64 11) nomerge, !dbg !52
  unreachable, !dbg !52
lua.ok.121:
  %t879 = icmp eq i32 %t856, %t869, !dbg !52
  %t880 = add i32 %t869, 1, !dbg !52
  %t881 = select i1 %t879, i32 %t880, i32 %t869, !dbg !52
  store i32 %t881, ptr %t853, !dbg !52
  %t882 = getelementptr inbounds { ptr, i32, i32, i32, i32 }, ptr %slot30, i32 0, i32 0, !dbg !52
  %t883 = load ptr, ptr %t882, !dbg !52
  %t884 = zext i32 %t856 to i64, !dbg !52
  %t885 = getelementptr inbounds i8, ptr %t883, i64 %t884, !dbg !52
  %t886 = trunc i32 %t868 to i8, !dbg !52
  store i8 %t886, ptr %t885, !dbg !52
  %t887 = getelementptr inbounds { ptr, i32, i32, i32, i32 }, ptr %slot30, i32 0, i32 2, !dbg !53
  %t888 = load i32, ptr %slot38, !dbg !53
  %t889 = call i32 @ks_encode_aot_helper_u32(double 0x4008000000000000), !dbg !53
  %t890 = call i32 @ks_encode_aot_helper_add(i32 %t888, i32 %t889), !dbg !53
  %t891 = call i32 @ks_encode_aot_helper_u32(double 0x404E800000000000), !dbg !53
  %t892 = load i32, ptr %t887, !dbg !53
  %t893 = getelementptr inbounds { ptr, i32, i32, i32, i32 }, ptr %slot30, i32 0, i32 1, !dbg !53
  %t894 = load i32, ptr %t893, !dbg !53
  %t895 = icmp ugt i32 %t890, %t892, !dbg !53
  %t896 = icmp uge i32 %t890, %t894, !dbg !53
  %t897 = or i1 %t895, %t896, !dbg !53
  %t898 = icmp ugt i32 %t891, 255, !dbg !53
  %t899 = or i1 %t897, %t898, !dbg !53
  br i1 %t899, label %lua.raise.122, label %lua.ok.123, !prof !7, !dbg !53
lua.raise.122:
  %t900 = getelementptr inbounds ptr, ptr %t1, i64 11, !dbg !53
  %rt.raise.901 = load ptr, ptr %t900, !invariant.load !8, !dbg !53
  call void %rt.raise.901(ptr %L, i64 11) nomerge, !dbg !53
  unreachable, !dbg !53
lua.ok.123:
  %t902 = icmp eq i32 %t890, %t892, !dbg !53
  %t903 = add i32 %t892, 1, !dbg !53
  %t904 = select i1 %t902, i32 %t903, i32 %t892, !dbg !53
  store i32 %t904, ptr %t887, !dbg !53
  %t905 = getelementptr inbounds { ptr, i32, i32, i32, i32 }, ptr %slot30, i32 0, i32 0, !dbg !53
  %t906 = load ptr, ptr %t905, !dbg !53
  %t907 = zext i32 %t890 to i64, !dbg !53
  %t908 = getelementptr inbounds i8, ptr %t906, i64 %t907, !dbg !53
  %t909 = trunc i32 %t891 to i8, !dbg !53
  store i8 %t909, ptr %t908, !dbg !53
  %t910 = load i32, ptr %slot38, !dbg !54
  %t911 = call i32 @ks_encode_aot_helper_u32(double 0x4010000000000000), !dbg !54
  %t912 = call i32 @ks_encode_aot_helper_add(i32 %t910, i32 %t911), !dbg !54
  store i32 %t912, ptr %slot38, !dbg !54
  br label %if.end.87, !dbg !54
if.else.105:
  br label %if.end.87, !dbg !54
if.end.87:
  %t913 = call i32 @ks_encode_aot_helper_u32(double 0x0000000000000000), !dbg !55
  %t914 = zext i32 %t913 to i64, !dbg !55
  %t915 = load i32, ptr %slot38, !dbg !55
  %t916 = zext i32 %t915 to i64, !dbg !55
  %t917 = getelementptr inbounds ptr, ptr %t1, i64 60, !dbg !55
  %rt.builder_string_scratch.918 = load ptr, ptr %t917, !invariant.load !8, !dbg !55
  call void %rt.builder_string_scratch.918(ptr %L, ptr %slot22, ptr %slot30, i64 %t914, i64 %t916, i64 1), !dbg !55
  %t919 = getelementptr inbounds ptr, ptr %t1, i64 65, !dbg !56
  %rt.builder_finish.920 = load ptr, ptr %t919, !invariant.load !8, !dbg !56
  call void %rt.builder_finish.920(ptr %L, ptr %slot22), !dbg !56
  ret i32 1, !dbg !56
}

define internal i32 @ks_decode_aot_helper_u32(double %h_a_value) #1 {
entry:
  br label %body
body:
  %t1 = call i32 @nupp.wrap.u32(double %h_a_value)
  ret i32 %t1
}

define internal i32 @ks_decode_aot_helper_add(i32 %h_a_a, i32 %h_a_b) #1 {
entry:
  br label %body
body:
  %t1 = add i32 %h_a_a, %h_a_b
  ret i32 %t1
}

define internal i32 @ks_decode_aot_helper_or_bits(i32 %h_a_a, i32 %h_a_b) #1 {
entry:
  br label %body
body:
  %t1 = or i32 %h_a_a, %h_a_b
  ret i32 %t1
}

define internal i32 @ks_decode_aot_helper_shl(i32 %h_a_value, i32 %h_a_count) #1 {
entry:
  br label %body
body:
  %t1 = and i32 %h_a_count, 31
  %t2 = shl i32 %h_a_value, %t1
  ret i32 %t2
}

define internal i32 @ks_decode_aot_helper_shr(i32 %h_a_value, i32 %h_a_count) #1 {
entry:
  br label %body
body:
  %t1 = and i32 %h_a_count, 31
  %t2 = lshr i32 %h_a_value, %t1
  ret i32 %t2
}

define internal i32 @ks_decode_aot_helper_and_bits(i32 %h_a_a, i32 %h_a_b) #1 {
entry:
  br label %body
body:
  %t1 = and i32 %h_a_a, %h_a_b
  ret i32 %t1
}

define internal i32 @ks_07af12f296a4e582_decode_aot__neon_lua(ptr %L) #0 !dbg !57 {
entry:
  %slot6 = alloca i64, align 8
  %slot13 = alloca i32, align 4
  %slot14 = alloca [4096 x i8], align 16
  %slot24 = alloca { ptr, i32, i32, i32, i32 }, align 8
  %slot32 = alloca i32, align 4
  %slot66 = alloca i32, align 4
  %slot68 = alloca i32, align 4
  %slot70 = alloca i32, align 4
  %slot72 = alloca i32, align 4
  %slot96 = alloca i32, align 4
  %slot114 = alloca i32, align 4
  %slot132 = alloca i32, align 4
  %slot150 = alloca i32, align 4
  %slot173 = alloca i32, align 4
  %slot274 = alloca i32, align 4
  %slot292 = alloca i32, align 4
  %slot294 = alloca i32, align 4
  %slot346 = alloca i32, align 4
  br label %body
body:
  %t1 = load ptr, ptr @ks.rt, !dbg !58
  %t2 = call i32 @lua_checkstack(ptr %L, i32 7), !dbg !58
  %t3 = icmp eq i32 %t2, 0, !dbg !58
  br i1 %t3, label %lua.raise.1, label %lua.ok.2, !prof !7, !dbg !58
lua.raise.1:
  %t4 = getelementptr inbounds ptr, ptr %t1, i64 11, !dbg !58
  %rt.raise.5 = load ptr, ptr %t4, !invariant.load !8, !dbg !58
  call void %rt.raise.5(ptr %L, i64 1) nomerge, !dbg !58
  unreachable, !dbg !58
lua.ok.2:
  %t7 = call ptr @luaL_checklstring(ptr %L, i32 1, ptr %slot6), !dbg !58
  %t8 = load i64, ptr %slot6, !dbg !58
  %t9 = icmp ugt i64 %t8, 4294967295, !dbg !59
  br i1 %t9, label %lua.raise.3, label %lua.ok.4, !prof !7, !dbg !59
lua.raise.3:
  %t10 = getelementptr inbounds ptr, ptr %t1, i64 11, !dbg !59
  %rt.raise.11 = load ptr, ptr %t10, !invariant.load !8, !dbg !59
  call void %rt.raise.11(ptr %L, i64 2) nomerge, !dbg !59
  unreachable, !dbg !59
lua.ok.4:
  %t12 = trunc i64 %t8 to i32, !dbg !59
  store i32 %t12, ptr %slot13, !dbg !59
  %t15 = call i32 @ks_decode_aot_helper_u32(double 0x4000000000000000), !dbg !60
  %t16 = zext i32 %t15 to i64, !dbg !60
  %t17 = load i32, ptr %slot13, !dbg !60
  %t18 = call i32 @ks_decode_aot_helper_u32(double 0x4010000000000000), !dbg !60
  %t19 = call i32 @ks_decode_aot_helper_add(i32 %t17, i32 %t18), !dbg !60
  %t20 = zext i32 %t19 to i64, !dbg !60
  %t21 = sext i32 2 to i64, !dbg !60
  %t22 = getelementptr inbounds ptr, ptr %t1, i64 47, !dbg !60
  %rt.builder_init.23 = load ptr, ptr %t22, !invariant.load !8, !dbg !60
  call void %rt.builder_init.23(ptr %L, ptr %slot14, i64 %t21, i64 0, i64 0, i64 %t16, i64 %t20, i64 0, i64 0, i64 0, i64 1), !dbg !60
  %t25 = load i32, ptr %slot13, !dbg !61
  %t26 = call i32 @ks_decode_aot_helper_u32(double 0x4010000000000000), !dbg !61
  %t27 = call i32 @ks_decode_aot_helper_add(i32 %t25, i32 %t26), !dbg !61
  %t28 = zext i32 %t27 to i64, !dbg !61
  %t29 = getelementptr inbounds ptr, ptr %t1, i64 37, !dbg !61
  %rt.scratch_u8.30 = load ptr, ptr %t29, !invariant.load !8, !dbg !61
  call void %rt.scratch_u8.30(ptr %L, ptr %slot24, i64 %t28), !dbg !61
  %t31 = call i32 @ks_decode_aot_helper_u32(double 0x0000000000000000), !dbg !62
  store i32 %t31, ptr %slot32, !dbg !62
  %t33 = load i32, ptr %slot13, !dbg !63
  %t34 = icmp ult i32 0, %t33, !dbg !63
  br i1 %t34, label %if.then.6, label %if.else.7, !dbg !63
if.then.6:
  %t35 = load i32, ptr %slot13, !dbg !64
  %t36 = call i32 @ks_decode_aot_helper_u32(double 0x3FF0000000000000), !dbg !64
  %t37 = sub i32 %t35, %t36, !dbg !64
  %t38 = zext i32 %t37 to i64, !dbg !64
  %t39 = icmp uge i64 %t38, %t8, !dbg !64
  br i1 %t39, label %lua.raise.9, label %lua.ok.10, !prof !7, !dbg !64
lua.raise.9:
  %t40 = getelementptr inbounds ptr, ptr %t1, i64 11, !dbg !64
  %rt.raise.41 = load ptr, ptr %t40, !invariant.load !8, !dbg !64
  call void %rt.raise.41(ptr %L, i64 3) nomerge, !dbg !64
  unreachable, !dbg !64
lua.ok.10:
  %t42 = getelementptr inbounds i8, ptr %t7, i64 %t38, !dbg !64
  %t43 = load i8, ptr %t42, !dbg !64
  %t44 = zext i8 %t43 to i32, !dbg !64
  %t45 = icmp eq i32 %t44, 61, !dbg !64
  br i1 %t45, label %if.then.11, label %if.else.12, !dbg !64
if.then.11:
  %t46 = call i32 @ks_decode_aot_helper_u32(double 0x3FF0000000000000), !dbg !65
  store i32 %t46, ptr %slot32, !dbg !65
  br label %if.end.8, !dbg !65
if.else.12:
  br label %if.end.8, !dbg !65
if.end.8:
  %t47 = load i32, ptr %slot32, !dbg !66
  %t48 = icmp eq i32 %t47, 1, !dbg !66
  br i1 %t48, label %and.rhs.14, label %and.end.15, !dbg !66
and.rhs.14:
  %t49 = load i32, ptr %slot13, !dbg !66
  %t50 = icmp ult i32 1, %t49, !dbg !66
  br label %and.end.15, !dbg !66
and.end.15:
  %t51 = phi i1 [ false, %if.end.8 ], [ %t50, %and.rhs.14 ], !dbg !66
  br i1 %t51, label %and.rhs.16, label %and.end.17, !dbg !66
and.rhs.16:
  %t52 = load i32, ptr %slot13, !dbg !66
  %t53 = call i32 @ks_decode_aot_helper_u32(double 0x4000000000000000), !dbg !66
  %t54 = sub i32 %t52, %t53, !dbg !66
  %t55 = zext i32 %t54 to i64, !dbg !66
  %t56 = icmp uge i64 %t55, %t8, !dbg !66
  br i1 %t56, label %lua.raise.18, label %lua.ok.19, !prof !7, !dbg !66
lua.raise.18:
  %t57 = getelementptr inbounds ptr, ptr %t1, i64 11, !dbg !66
  %rt.raise.58 = load ptr, ptr %t57, !invariant.load !8, !dbg !66
  call void %rt.raise.58(ptr %L, i64 3) nomerge, !dbg !66
  unreachable, !dbg !66
lua.ok.19:
  %t59 = getelementptr inbounds i8, ptr %t7, i64 %t55, !dbg !66
  %t60 = load i8, ptr %t59, !dbg !66
  %t61 = zext i8 %t60 to i32, !dbg !66
  %t62 = icmp eq i32 %t61, 61, !dbg !66
  br label %and.end.17, !dbg !66
and.end.17:
  %t63 = phi i1 [ false, %and.end.15 ], [ %t62, %lua.ok.19 ], !dbg !66
  br i1 %t63, label %if.then.20, label %if.else.21, !dbg !66
if.then.20:
  %t64 = call i32 @ks_decode_aot_helper_u32(double 0x4000000000000000), !dbg !67
  store i32 %t64, ptr %slot32, !dbg !67
  br label %if.end.13, !dbg !67
if.else.21:
  br label %if.end.13, !dbg !67
if.end.13:
  br label %if.end.5, !dbg !67
if.else.7:
  br label %if.end.5, !dbg !67
if.end.5:
  %t65 = call i32 @ks_decode_aot_helper_u32(double 0x0000000000000000), !dbg !68
  store i32 %t65, ptr %slot66, !dbg !68
  %t67 = call i32 @ks_decode_aot_helper_u32(double 0x0000000000000000), !dbg !69
  store i32 %t67, ptr %slot68, !dbg !69
  %t69 = call i32 @ks_decode_aot_helper_u32(double 0x0000000000000000), !dbg !70
  store i32 %t69, ptr %slot70, !dbg !70
  %t71 = load i32, ptr %slot13, !dbg !71
  store i32 %t71, ptr %slot72, !dbg !71
  %t73 = load i32, ptr %slot32, !dbg !72
  %t74 = icmp ugt i32 %t73, 0, !dbg !72
  br i1 %t74, label %if.then.23, label %if.else.24, !dbg !72
if.then.23:
  %t75 = load i32, ptr %slot13, !dbg !73
  %t76 = call i32 @ks_decode_aot_helper_u32(double 0x4010000000000000), !dbg !73
  %t77 = sub i32 %t75, %t76, !dbg !73
  store i32 %t77, ptr %slot72, !dbg !73
  br label %if.end.22, !dbg !73
if.else.24:
  br label %if.end.22, !dbg !73
if.end.22:
  br label %while.head.25, !dbg !74
while.head.25:
  %t78 = load i32, ptr %slot66, !dbg !74
  %t79 = load i32, ptr %slot72, !dbg !74
  %t80 = icmp ult i32 %t78, %t79, !dbg !74
  br i1 %t80, label %while.body.26, label %while.end.27, !dbg !74
while.body.26:
  %t81 = load i32, ptr %slot66, !dbg !75
  %t82 = zext i32 %t81 to i64, !dbg !75
  %t83 = icmp uge i64 %t82, %t8, !dbg !75
  br i1 %t83, label %lua.raise.28, label %lua.ok.29, !prof !7, !dbg !75
lua.raise.28:
  %t84 = getelementptr inbounds ptr, ptr %t1, i64 11, !dbg !75
  %rt.raise.85 = load ptr, ptr %t84, !invariant.load !8, !dbg !75
  call void %rt.raise.85(ptr %L, i64 3) nomerge, !dbg !75
  unreachable, !dbg !75
lua.ok.29:
  %t86 = getelementptr inbounds i8, ptr %t7, i64 %t82, !dbg !75
  %t87 = load i8, ptr %t86, !dbg !75
  %t88 = zext i8 %t87 to i32, !dbg !75
  %t89 = zext i32 %t88 to i64, !dbg !75
  %t90 = icmp uge i64 %t89, 256, !dbg !75
  br i1 %t90, label %lua.raise.30, label %lua.ok.31, !prof !7, !dbg !75
lua.raise.30:
  %t91 = getelementptr inbounds ptr, ptr %t1, i64 11, !dbg !75
  %rt.raise.92 = load ptr, ptr %t91, !invariant.load !8, !dbg !75
  call void %rt.raise.92(ptr %L, i64 3) nomerge, !dbg !75
  unreachable, !dbg !75
lua.ok.31:
  %t93 = getelementptr inbounds i8, ptr @nupp.bytes.2, i64 %t89, !dbg !75
  %t94 = load i8, ptr %t93, !dbg !75
  %t95 = zext i8 %t94 to i32, !dbg !75
  store i32 %t95, ptr %slot96, !dbg !75
  %t97 = load i32, ptr %slot66, !dbg !76
  %t98 = call i32 @ks_decode_aot_helper_u32(double 0x3FF0000000000000), !dbg !76
  %t99 = call i32 @ks_decode_aot_helper_add(i32 %t97, i32 %t98), !dbg !76
  %t100 = zext i32 %t99 to i64, !dbg !76
  %t101 = icmp uge i64 %t100, %t8, !dbg !76
  br i1 %t101, label %lua.raise.32, label %lua.ok.33, !prof !7, !dbg !76
lua.raise.32:
  %t102 = getelementptr inbounds ptr, ptr %t1, i64 11, !dbg !76
  %rt.raise.103 = load ptr, ptr %t102, !invariant.load !8, !dbg !76
  call void %rt.raise.103(ptr %L, i64 3) nomerge, !dbg !76
  unreachable, !dbg !76
lua.ok.33:
  %t104 = getelementptr inbounds i8, ptr %t7, i64 %t100, !dbg !76
  %t105 = load i8, ptr %t104, !dbg !76
  %t106 = zext i8 %t105 to i32, !dbg !76
  %t107 = zext i32 %t106 to i64, !dbg !76
  %t108 = icmp uge i64 %t107, 256, !dbg !76
  br i1 %t108, label %lua.raise.34, label %lua.ok.35, !prof !7, !dbg !76
lua.raise.34:
  %t109 = getelementptr inbounds ptr, ptr %t1, i64 11, !dbg !76
  %rt.raise.110 = load ptr, ptr %t109, !invariant.load !8, !dbg !76
  call void %rt.raise.110(ptr %L, i64 3) nomerge, !dbg !76
  unreachable, !dbg !76
lua.ok.35:
  %t111 = getelementptr inbounds i8, ptr @nupp.bytes.2, i64 %t107, !dbg !76
  %t112 = load i8, ptr %t111, !dbg !76
  %t113 = zext i8 %t112 to i32, !dbg !76
  store i32 %t113, ptr %slot114, !dbg !76
  %t115 = load i32, ptr %slot66, !dbg !77
  %t116 = call i32 @ks_decode_aot_helper_u32(double 0x4000000000000000), !dbg !77
  %t117 = call i32 @ks_decode_aot_helper_add(i32 %t115, i32 %t116), !dbg !77
  %t118 = zext i32 %t117 to i64, !dbg !77
  %t119 = icmp uge i64 %t118, %t8, !dbg !77
  br i1 %t119, label %lua.raise.36, label %lua.ok.37, !prof !7, !dbg !77
lua.raise.36:
  %t120 = getelementptr inbounds ptr, ptr %t1, i64 11, !dbg !77
  %rt.raise.121 = load ptr, ptr %t120, !invariant.load !8, !dbg !77
  call void %rt.raise.121(ptr %L, i64 3) nomerge, !dbg !77
  unreachable, !dbg !77
lua.ok.37:
  %t122 = getelementptr inbounds i8, ptr %t7, i64 %t118, !dbg !77
  %t123 = load i8, ptr %t122, !dbg !77
  %t124 = zext i8 %t123 to i32, !dbg !77
  %t125 = zext i32 %t124 to i64, !dbg !77
  %t126 = icmp uge i64 %t125, 256, !dbg !77
  br i1 %t126, label %lua.raise.38, label %lua.ok.39, !prof !7, !dbg !77
lua.raise.38:
  %t127 = getelementptr inbounds ptr, ptr %t1, i64 11, !dbg !77
  %rt.raise.128 = load ptr, ptr %t127, !invariant.load !8, !dbg !77
  call void %rt.raise.128(ptr %L, i64 3) nomerge, !dbg !77
  unreachable, !dbg !77
lua.ok.39:
  %t129 = getelementptr inbounds i8, ptr @nupp.bytes.2, i64 %t125, !dbg !77
  %t130 = load i8, ptr %t129, !dbg !77
  %t131 = zext i8 %t130 to i32, !dbg !77
  store i32 %t131, ptr %slot132, !dbg !77
  %t133 = load i32, ptr %slot66, !dbg !78
  %t134 = call i32 @ks_decode_aot_helper_u32(double 0x4008000000000000), !dbg !78
  %t135 = call i32 @ks_decode_aot_helper_add(i32 %t133, i32 %t134), !dbg !78
  %t136 = zext i32 %t135 to i64, !dbg !78
  %t137 = icmp uge i64 %t136, %t8, !dbg !78
  br i1 %t137, label %lua.raise.40, label %lua.ok.41, !prof !7, !dbg !78
lua.raise.40:
  %t138 = getelementptr inbounds ptr, ptr %t1, i64 11, !dbg !78
  %rt.raise.139 = load ptr, ptr %t138, !invariant.load !8, !dbg !78
  call void %rt.raise.139(ptr %L, i64 3) nomerge, !dbg !78
  unreachable, !dbg !78
lua.ok.41:
  %t140 = getelementptr inbounds i8, ptr %t7, i64 %t136, !dbg !78
  %t141 = load i8, ptr %t140, !dbg !78
  %t142 = zext i8 %t141 to i32, !dbg !78
  %t143 = zext i32 %t142 to i64, !dbg !78
  %t144 = icmp uge i64 %t143, 256, !dbg !78
  br i1 %t144, label %lua.raise.42, label %lua.ok.43, !prof !7, !dbg !78
lua.raise.42:
  %t145 = getelementptr inbounds ptr, ptr %t1, i64 11, !dbg !78
  %rt.raise.146 = load ptr, ptr %t145, !invariant.load !8, !dbg !78
  call void %rt.raise.146(ptr %L, i64 3) nomerge, !dbg !78
  unreachable, !dbg !78
lua.ok.43:
  %t147 = getelementptr inbounds i8, ptr @nupp.bytes.2, i64 %t143, !dbg !78
  %t148 = load i8, ptr %t147, !dbg !78
  %t149 = zext i8 %t148 to i32, !dbg !78
  store i32 %t149, ptr %slot150, !dbg !78
  %t151 = load i32, ptr %slot70, !dbg !79
  %t152 = load i32, ptr %slot96, !dbg !79
  %t153 = load i32, ptr %slot114, !dbg !79
  %t154 = call i32 @ks_decode_aot_helper_or_bits(i32 %t152, i32 %t153), !dbg !79
  %t155 = load i32, ptr %slot132, !dbg !79
  %t156 = load i32, ptr %slot150, !dbg !79
  %t157 = call i32 @ks_decode_aot_helper_or_bits(i32 %t155, i32 %t156), !dbg !79
  %t158 = call i32 @ks_decode_aot_helper_or_bits(i32 %t154, i32 %t157), !dbg !79
  %t159 = call i32 @ks_decode_aot_helper_or_bits(i32 %t151, i32 %t158), !dbg !79
  store i32 %t159, ptr %slot70, !dbg !79
  %t160 = load i32, ptr %slot96, !dbg !80
  %t161 = call i32 @ks_decode_aot_helper_u32(double 0x4032000000000000), !dbg !80
  %t162 = call i32 @ks_decode_aot_helper_shl(i32 %t160, i32 %t161), !dbg !80
  %t163 = load i32, ptr %slot114, !dbg !80
  %t164 = call i32 @ks_decode_aot_helper_u32(double 0x4028000000000000), !dbg !80
  %t165 = call i32 @ks_decode_aot_helper_shl(i32 %t163, i32 %t164), !dbg !80
  %t166 = call i32 @ks_decode_aot_helper_or_bits(i32 %t162, i32 %t165), !dbg !80
  %t167 = load i32, ptr %slot132, !dbg !80
  %t168 = call i32 @ks_decode_aot_helper_u32(double 0x4018000000000000), !dbg !80
  %t169 = call i32 @ks_decode_aot_helper_shl(i32 %t167, i32 %t168), !dbg !80
  %t170 = load i32, ptr %slot150, !dbg !80
  %t171 = call i32 @ks_decode_aot_helper_or_bits(i32 %t169, i32 %t170), !dbg !80
  %t172 = call i32 @ks_decode_aot_helper_or_bits(i32 %t166, i32 %t171), !dbg !80
  store i32 %t172, ptr %slot173, !dbg !80
  %t174 = getelementptr inbounds { ptr, i32, i32, i32, i32 }, ptr %slot24, i32 0, i32 2, !dbg !81
  %t175 = load i32, ptr %slot68, !dbg !81
  %t176 = load i32, ptr %slot173, !dbg !81
  %t177 = call i32 @ks_decode_aot_helper_u32(double 0x4030000000000000), !dbg !81
  %t178 = call i32 @ks_decode_aot_helper_shr(i32 %t176, i32 %t177), !dbg !81
  %t179 = call i32 @ks_decode_aot_helper_u32(double 0x406FE00000000000), !dbg !81
  %t180 = call i32 @ks_decode_aot_helper_and_bits(i32 %t178, i32 %t179), !dbg !81
  %t181 = load i32, ptr %t174, !dbg !81
  %t182 = getelementptr inbounds { ptr, i32, i32, i32, i32 }, ptr %slot24, i32 0, i32 1, !dbg !81
  %t183 = load i32, ptr %t182, !dbg !81
  %t184 = icmp ugt i32 %t175, %t181, !dbg !81
  %t185 = icmp uge i32 %t175, %t183, !dbg !81
  %t186 = or i1 %t184, %t185, !dbg !81
  %t187 = icmp ugt i32 %t180, 255, !dbg !81
  %t188 = or i1 %t186, %t187, !dbg !81
  br i1 %t188, label %lua.raise.44, label %lua.ok.45, !prof !7, !dbg !81
lua.raise.44:
  %t189 = getelementptr inbounds ptr, ptr %t1, i64 11, !dbg !81
  %rt.raise.190 = load ptr, ptr %t189, !invariant.load !8, !dbg !81
  call void %rt.raise.190(ptr %L, i64 11) nomerge, !dbg !81
  unreachable, !dbg !81
lua.ok.45:
  %t191 = icmp eq i32 %t175, %t181, !dbg !81
  %t192 = add i32 %t181, 1, !dbg !81
  %t193 = select i1 %t191, i32 %t192, i32 %t181, !dbg !81
  store i32 %t193, ptr %t174, !dbg !81
  %t194 = getelementptr inbounds { ptr, i32, i32, i32, i32 }, ptr %slot24, i32 0, i32 0, !dbg !81
  %t195 = load ptr, ptr %t194, !dbg !81
  %t196 = zext i32 %t175 to i64, !dbg !81
  %t197 = getelementptr inbounds i8, ptr %t195, i64 %t196, !dbg !81
  %t198 = trunc i32 %t180 to i8, !dbg !81
  store i8 %t198, ptr %t197, !dbg !81
  %t199 = getelementptr inbounds { ptr, i32, i32, i32, i32 }, ptr %slot24, i32 0, i32 2, !dbg !82
  %t200 = load i32, ptr %slot68, !dbg !82
  %t201 = call i32 @ks_decode_aot_helper_u32(double 0x3FF0000000000000), !dbg !82
  %t202 = call i32 @ks_decode_aot_helper_add(i32 %t200, i32 %t201), !dbg !82
  %t203 = load i32, ptr %slot173, !dbg !82
  %t204 = call i32 @ks_decode_aot_helper_u32(double 0x4020000000000000), !dbg !82
  %t205 = call i32 @ks_decode_aot_helper_shr(i32 %t203, i32 %t204), !dbg !82
  %t206 = call i32 @ks_decode_aot_helper_u32(double 0x406FE00000000000), !dbg !82
  %t207 = call i32 @ks_decode_aot_helper_and_bits(i32 %t205, i32 %t206), !dbg !82
  %t208 = load i32, ptr %t199, !dbg !82
  %t209 = getelementptr inbounds { ptr, i32, i32, i32, i32 }, ptr %slot24, i32 0, i32 1, !dbg !82
  %t210 = load i32, ptr %t209, !dbg !82
  %t211 = icmp ugt i32 %t202, %t208, !dbg !82
  %t212 = icmp uge i32 %t202, %t210, !dbg !82
  %t213 = or i1 %t211, %t212, !dbg !82
  %t214 = icmp ugt i32 %t207, 255, !dbg !82
  %t215 = or i1 %t213, %t214, !dbg !82
  br i1 %t215, label %lua.raise.46, label %lua.ok.47, !prof !7, !dbg !82
lua.raise.46:
  %t216 = getelementptr inbounds ptr, ptr %t1, i64 11, !dbg !82
  %rt.raise.217 = load ptr, ptr %t216, !invariant.load !8, !dbg !82
  call void %rt.raise.217(ptr %L, i64 11) nomerge, !dbg !82
  unreachable, !dbg !82
lua.ok.47:
  %t218 = icmp eq i32 %t202, %t208, !dbg !82
  %t219 = add i32 %t208, 1, !dbg !82
  %t220 = select i1 %t218, i32 %t219, i32 %t208, !dbg !82
  store i32 %t220, ptr %t199, !dbg !82
  %t221 = getelementptr inbounds { ptr, i32, i32, i32, i32 }, ptr %slot24, i32 0, i32 0, !dbg !82
  %t222 = load ptr, ptr %t221, !dbg !82
  %t223 = zext i32 %t202 to i64, !dbg !82
  %t224 = getelementptr inbounds i8, ptr %t222, i64 %t223, !dbg !82
  %t225 = trunc i32 %t207 to i8, !dbg !82
  store i8 %t225, ptr %t224, !dbg !82
  %t226 = getelementptr inbounds { ptr, i32, i32, i32, i32 }, ptr %slot24, i32 0, i32 2, !dbg !83
  %t227 = load i32, ptr %slot68, !dbg !83
  %t228 = call i32 @ks_decode_aot_helper_u32(double 0x4000000000000000), !dbg !83
  %t229 = call i32 @ks_decode_aot_helper_add(i32 %t227, i32 %t228), !dbg !83
  %t230 = load i32, ptr %slot173, !dbg !83
  %t231 = call i32 @ks_decode_aot_helper_u32(double 0x406FE00000000000), !dbg !83
  %t232 = call i32 @ks_decode_aot_helper_and_bits(i32 %t230, i32 %t231), !dbg !83
  %t233 = load i32, ptr %t226, !dbg !83
  %t234 = getelementptr inbounds { ptr, i32, i32, i32, i32 }, ptr %slot24, i32 0, i32 1, !dbg !83
  %t235 = load i32, ptr %t234, !dbg !83
  %t236 = icmp ugt i32 %t229, %t233, !dbg !83
  %t237 = icmp uge i32 %t229, %t235, !dbg !83
  %t238 = or i1 %t236, %t237, !dbg !83
  %t239 = icmp ugt i32 %t232, 255, !dbg !83
  %t240 = or i1 %t238, %t239, !dbg !83
  br i1 %t240, label %lua.raise.48, label %lua.ok.49, !prof !7, !dbg !83
lua.raise.48:
  %t241 = getelementptr inbounds ptr, ptr %t1, i64 11, !dbg !83
  %rt.raise.242 = load ptr, ptr %t241, !invariant.load !8, !dbg !83
  call void %rt.raise.242(ptr %L, i64 11) nomerge, !dbg !83
  unreachable, !dbg !83
lua.ok.49:
  %t243 = icmp eq i32 %t229, %t233, !dbg !83
  %t244 = add i32 %t233, 1, !dbg !83
  %t245 = select i1 %t243, i32 %t244, i32 %t233, !dbg !83
  store i32 %t245, ptr %t226, !dbg !83
  %t246 = getelementptr inbounds { ptr, i32, i32, i32, i32 }, ptr %slot24, i32 0, i32 0, !dbg !83
  %t247 = load ptr, ptr %t246, !dbg !83
  %t248 = zext i32 %t229 to i64, !dbg !83
  %t249 = getelementptr inbounds i8, ptr %t247, i64 %t248, !dbg !83
  %t250 = trunc i32 %t232 to i8, !dbg !83
  store i8 %t250, ptr %t249, !dbg !83
  %t251 = load i32, ptr %slot66, !dbg !84
  %t252 = call i32 @ks_decode_aot_helper_u32(double 0x4010000000000000), !dbg !84
  %t253 = call i32 @ks_decode_aot_helper_add(i32 %t251, i32 %t252), !dbg !84
  store i32 %t253, ptr %slot66, !dbg !84
  %t254 = load i32, ptr %slot68, !dbg !85
  %t255 = call i32 @ks_decode_aot_helper_u32(double 0x4008000000000000), !dbg !85
  %t256 = call i32 @ks_decode_aot_helper_add(i32 %t254, i32 %t255), !dbg !85
  store i32 %t256, ptr %slot68, !dbg !85
  br label %while.head.25, !dbg !85
while.end.27:
  %t257 = load i32, ptr %slot32, !dbg !86
  %t258 = icmp ugt i32 %t257, 0, !dbg !86
  br i1 %t258, label %if.then.51, label %if.else.52, !dbg !86
if.then.51:
  %t259 = load i32, ptr %slot66, !dbg !87
  %t260 = zext i32 %t259 to i64, !dbg !87
  %t261 = icmp uge i64 %t260, %t8, !dbg !87
  br i1 %t261, label %lua.raise.53, label %lua.ok.54, !prof !7, !dbg !87
lua.raise.53:
  %t262 = getelementptr inbounds ptr, ptr %t1, i64 11, !dbg !87
  %rt.raise.263 = load ptr, ptr %t262, !invariant.load !8, !dbg !87
  call void %rt.raise.263(ptr %L, i64 3) nomerge, !dbg !87
  unreachable, !dbg !87
lua.ok.54:
  %t264 = getelementptr inbounds i8, ptr %t7, i64 %t260, !dbg !87
  %t265 = load i8, ptr %t264, !dbg !87
  %t266 = zext i8 %t265 to i32, !dbg !87
  %t267 = zext i32 %t266 to i64, !dbg !87
  %t268 = icmp uge i64 %t267, 256, !dbg !87
  br i1 %t268, label %lua.raise.55, label %lua.ok.56, !prof !7, !dbg !87
lua.raise.55:
  %t269 = getelementptr inbounds ptr, ptr %t1, i64 11, !dbg !87
  %rt.raise.270 = load ptr, ptr %t269, !invariant.load !8, !dbg !87
  call void %rt.raise.270(ptr %L, i64 3) nomerge, !dbg !87
  unreachable, !dbg !87
lua.ok.56:
  %t271 = getelementptr inbounds i8, ptr @nupp.bytes.2, i64 %t267, !dbg !87
  %t272 = load i8, ptr %t271, !dbg !87
  %t273 = zext i8 %t272 to i32, !dbg !87
  store i32 %t273, ptr %slot274, !dbg !87
  %t275 = load i32, ptr %slot66, !dbg !88
  %t276 = call i32 @ks_decode_aot_helper_u32(double 0x3FF0000000000000), !dbg !88
  %t277 = call i32 @ks_decode_aot_helper_add(i32 %t275, i32 %t276), !dbg !88
  %t278 = zext i32 %t277 to i64, !dbg !88
  %t279 = icmp uge i64 %t278, %t8, !dbg !88
  br i1 %t279, label %lua.raise.57, label %lua.ok.58, !prof !7, !dbg !88
lua.raise.57:
  %t280 = getelementptr inbounds ptr, ptr %t1, i64 11, !dbg !88
  %rt.raise.281 = load ptr, ptr %t280, !invariant.load !8, !dbg !88
  call void %rt.raise.281(ptr %L, i64 3) nomerge, !dbg !88
  unreachable, !dbg !88
lua.ok.58:
  %t282 = getelementptr inbounds i8, ptr %t7, i64 %t278, !dbg !88
  %t283 = load i8, ptr %t282, !dbg !88
  %t284 = zext i8 %t283 to i32, !dbg !88
  %t285 = zext i32 %t284 to i64, !dbg !88
  %t286 = icmp uge i64 %t285, 256, !dbg !88
  br i1 %t286, label %lua.raise.59, label %lua.ok.60, !prof !7, !dbg !88
lua.raise.59:
  %t287 = getelementptr inbounds ptr, ptr %t1, i64 11, !dbg !88
  %rt.raise.288 = load ptr, ptr %t287, !invariant.load !8, !dbg !88
  call void %rt.raise.288(ptr %L, i64 3) nomerge, !dbg !88
  unreachable, !dbg !88
lua.ok.60:
  %t289 = getelementptr inbounds i8, ptr @nupp.bytes.2, i64 %t285, !dbg !88
  %t290 = load i8, ptr %t289, !dbg !88
  %t291 = zext i8 %t290 to i32, !dbg !88
  store i32 %t291, ptr %slot292, !dbg !88
  %t293 = call i32 @ks_decode_aot_helper_u32(double 0x0000000000000000), !dbg !89
  store i32 %t293, ptr %slot294, !dbg !89
  %t295 = load i32, ptr %slot32, !dbg !90
  %t296 = icmp eq i32 %t295, 1, !dbg !90
  br i1 %t296, label %if.then.62, label %if.else.63, !dbg !90
if.then.62:
  %t297 = load i32, ptr %slot66, !dbg !91
  %t298 = call i32 @ks_decode_aot_helper_u32(double 0x4000000000000000), !dbg !91
  %t299 = call i32 @ks_decode_aot_helper_add(i32 %t297, i32 %t298), !dbg !91
  %t300 = zext i32 %t299 to i64, !dbg !91
  %t301 = icmp uge i64 %t300, %t8, !dbg !91
  br i1 %t301, label %lua.raise.64, label %lua.ok.65, !prof !7, !dbg !91
lua.raise.64:
  %t302 = getelementptr inbounds ptr, ptr %t1, i64 11, !dbg !91
  %rt.raise.303 = load ptr, ptr %t302, !invariant.load !8, !dbg !91
  call void %rt.raise.303(ptr %L, i64 3) nomerge, !dbg !91
  unreachable, !dbg !91
lua.ok.65:
  %t304 = getelementptr inbounds i8, ptr %t7, i64 %t300, !dbg !91
  %t305 = load i8, ptr %t304, !dbg !91
  %t306 = zext i8 %t305 to i32, !dbg !91
  %t307 = zext i32 %t306 to i64, !dbg !91
  %t308 = icmp uge i64 %t307, 256, !dbg !91
  br i1 %t308, label %lua.raise.66, label %lua.ok.67, !prof !7, !dbg !91
lua.raise.66:
  %t309 = getelementptr inbounds ptr, ptr %t1, i64 11, !dbg !91
  %rt.raise.310 = load ptr, ptr %t309, !invariant.load !8, !dbg !91
  call void %rt.raise.310(ptr %L, i64 3) nomerge, !dbg !91
  unreachable, !dbg !91
lua.ok.67:
  %t311 = getelementptr inbounds i8, ptr @nupp.bytes.2, i64 %t307, !dbg !91
  %t312 = load i8, ptr %t311, !dbg !91
  %t313 = zext i8 %t312 to i32, !dbg !91
  store i32 %t313, ptr %slot294, !dbg !91
  %t314 = load i32, ptr %slot70, !dbg !92
  %t315 = load i32, ptr %slot294, !dbg !92
  %t316 = call i32 @ks_decode_aot_helper_u32(double 0x4008000000000000), !dbg !92
  %t317 = call i32 @ks_decode_aot_helper_and_bits(i32 %t315, i32 %t316), !dbg !92
  %t318 = call i32 @ks_decode_aot_helper_u32(double 0x4018000000000000), !dbg !92
  %t319 = call i32 @ks_decode_aot_helper_shl(i32 %t317, i32 %t318), !dbg !92
  %t320 = call i32 @ks_decode_aot_helper_or_bits(i32 %t314, i32 %t319), !dbg !92
  store i32 %t320, ptr %slot70, !dbg !92
  br label %if.end.61, !dbg !92
if.else.63:
  %t321 = load i32, ptr %slot70, !dbg !93
  %t322 = load i32, ptr %slot292, !dbg !93
  %t323 = call i32 @ks_decode_aot_helper_u32(double 0x402E000000000000), !dbg !93
  %t324 = call i32 @ks_decode_aot_helper_and_bits(i32 %t322, i32 %t323), !dbg !93
  %t325 = call i32 @ks_decode_aot_helper_u32(double 0x4018000000000000), !dbg !93
  %t326 = call i32 @ks_decode_aot_helper_shl(i32 %t324, i32 %t325), !dbg !93
  %t327 = call i32 @ks_decode_aot_helper_or_bits(i32 %t321, i32 %t326), !dbg !93
  store i32 %t327, ptr %slot70, !dbg !93
  br label %if.end.61, !dbg !93
if.end.61:
  %t328 = load i32, ptr %slot70, !dbg !94
  %t329 = load i32, ptr %slot274, !dbg !94
  %t330 = load i32, ptr %slot292, !dbg !94
  %t331 = call i32 @ks_decode_aot_helper_or_bits(i32 %t329, i32 %t330), !dbg !94
  %t332 = load i32, ptr %slot294, !dbg !94
  %t333 = call i32 @ks_decode_aot_helper_or_bits(i32 %t331, i32 %t332), !dbg !94
  %t334 = call i32 @ks_decode_aot_helper_or_bits(i32 %t328, i32 %t333), !dbg !94
  store i32 %t334, ptr %slot70, !dbg !94
  %t335 = load i32, ptr %slot274, !dbg !95
  %t336 = call i32 @ks_decode_aot_helper_u32(double 0x4032000000000000), !dbg !95
  %t337 = call i32 @ks_decode_aot_helper_shl(i32 %t335, i32 %t336), !dbg !95
  %t338 = load i32, ptr %slot292, !dbg !95
  %t339 = call i32 @ks_decode_aot_helper_u32(double 0x4028000000000000), !dbg !95
  %t340 = call i32 @ks_decode_aot_helper_shl(i32 %t338, i32 %t339), !dbg !95
  %t341 = call i32 @ks_decode_aot_helper_or_bits(i32 %t337, i32 %t340), !dbg !95
  %t342 = load i32, ptr %slot294, !dbg !95
  %t343 = call i32 @ks_decode_aot_helper_u32(double 0x4018000000000000), !dbg !95
  %t344 = call i32 @ks_decode_aot_helper_shl(i32 %t342, i32 %t343), !dbg !95
  %t345 = call i32 @ks_decode_aot_helper_or_bits(i32 %t341, i32 %t344), !dbg !95
  store i32 %t345, ptr %slot346, !dbg !95
  %t347 = getelementptr inbounds { ptr, i32, i32, i32, i32 }, ptr %slot24, i32 0, i32 2, !dbg !96
  %t348 = load i32, ptr %slot68, !dbg !96
  %t349 = load i32, ptr %slot346, !dbg !96
  %t350 = call i32 @ks_decode_aot_helper_u32(double 0x4030000000000000), !dbg !96
  %t351 = call i32 @ks_decode_aot_helper_shr(i32 %t349, i32 %t350), !dbg !96
  %t352 = call i32 @ks_decode_aot_helper_u32(double 0x406FE00000000000), !dbg !96
  %t353 = call i32 @ks_decode_aot_helper_and_bits(i32 %t351, i32 %t352), !dbg !96
  %t354 = load i32, ptr %t347, !dbg !96
  %t355 = getelementptr inbounds { ptr, i32, i32, i32, i32 }, ptr %slot24, i32 0, i32 1, !dbg !96
  %t356 = load i32, ptr %t355, !dbg !96
  %t357 = icmp ugt i32 %t348, %t354, !dbg !96
  %t358 = icmp uge i32 %t348, %t356, !dbg !96
  %t359 = or i1 %t357, %t358, !dbg !96
  %t360 = icmp ugt i32 %t353, 255, !dbg !96
  %t361 = or i1 %t359, %t360, !dbg !96
  br i1 %t361, label %lua.raise.68, label %lua.ok.69, !prof !7, !dbg !96
lua.raise.68:
  %t362 = getelementptr inbounds ptr, ptr %t1, i64 11, !dbg !96
  %rt.raise.363 = load ptr, ptr %t362, !invariant.load !8, !dbg !96
  call void %rt.raise.363(ptr %L, i64 11) nomerge, !dbg !96
  unreachable, !dbg !96
lua.ok.69:
  %t364 = icmp eq i32 %t348, %t354, !dbg !96
  %t365 = add i32 %t354, 1, !dbg !96
  %t366 = select i1 %t364, i32 %t365, i32 %t354, !dbg !96
  store i32 %t366, ptr %t347, !dbg !96
  %t367 = getelementptr inbounds { ptr, i32, i32, i32, i32 }, ptr %slot24, i32 0, i32 0, !dbg !96
  %t368 = load ptr, ptr %t367, !dbg !96
  %t369 = zext i32 %t348 to i64, !dbg !96
  %t370 = getelementptr inbounds i8, ptr %t368, i64 %t369, !dbg !96
  %t371 = trunc i32 %t353 to i8, !dbg !96
  store i8 %t371, ptr %t370, !dbg !96
  %t372 = load i32, ptr %slot68, !dbg !97
  %t373 = call i32 @ks_decode_aot_helper_u32(double 0x3FF0000000000000), !dbg !97
  %t374 = call i32 @ks_decode_aot_helper_add(i32 %t372, i32 %t373), !dbg !97
  store i32 %t374, ptr %slot68, !dbg !97
  %t375 = load i32, ptr %slot32, !dbg !98
  %t376 = icmp eq i32 %t375, 1, !dbg !98
  br i1 %t376, label %if.then.71, label %if.else.72, !dbg !98
if.then.71:
  %t377 = getelementptr inbounds { ptr, i32, i32, i32, i32 }, ptr %slot24, i32 0, i32 2, !dbg !99
  %t378 = load i32, ptr %slot68, !dbg !99
  %t379 = load i32, ptr %slot346, !dbg !99
  %t380 = call i32 @ks_decode_aot_helper_u32(double 0x4020000000000000), !dbg !99
  %t381 = call i32 @ks_decode_aot_helper_shr(i32 %t379, i32 %t380), !dbg !99
  %t382 = call i32 @ks_decode_aot_helper_u32(double 0x406FE00000000000), !dbg !99
  %t383 = call i32 @ks_decode_aot_helper_and_bits(i32 %t381, i32 %t382), !dbg !99
  %t384 = load i32, ptr %t377, !dbg !99
  %t385 = getelementptr inbounds { ptr, i32, i32, i32, i32 }, ptr %slot24, i32 0, i32 1, !dbg !99
  %t386 = load i32, ptr %t385, !dbg !99
  %t387 = icmp ugt i32 %t378, %t384, !dbg !99
  %t388 = icmp uge i32 %t378, %t386, !dbg !99
  %t389 = or i1 %t387, %t388, !dbg !99
  %t390 = icmp ugt i32 %t383, 255, !dbg !99
  %t391 = or i1 %t389, %t390, !dbg !99
  br i1 %t391, label %lua.raise.73, label %lua.ok.74, !prof !7, !dbg !99
lua.raise.73:
  %t392 = getelementptr inbounds ptr, ptr %t1, i64 11, !dbg !99
  %rt.raise.393 = load ptr, ptr %t392, !invariant.load !8, !dbg !99
  call void %rt.raise.393(ptr %L, i64 11) nomerge, !dbg !99
  unreachable, !dbg !99
lua.ok.74:
  %t394 = icmp eq i32 %t378, %t384, !dbg !99
  %t395 = add i32 %t384, 1, !dbg !99
  %t396 = select i1 %t394, i32 %t395, i32 %t384, !dbg !99
  store i32 %t396, ptr %t377, !dbg !99
  %t397 = getelementptr inbounds { ptr, i32, i32, i32, i32 }, ptr %slot24, i32 0, i32 0, !dbg !99
  %t398 = load ptr, ptr %t397, !dbg !99
  %t399 = zext i32 %t378 to i64, !dbg !99
  %t400 = getelementptr inbounds i8, ptr %t398, i64 %t399, !dbg !99
  %t401 = trunc i32 %t383 to i8, !dbg !99
  store i8 %t401, ptr %t400, !dbg !99
  %t402 = load i32, ptr %slot68, !dbg !100
  %t403 = call i32 @ks_decode_aot_helper_u32(double 0x3FF0000000000000), !dbg !100
  %t404 = call i32 @ks_decode_aot_helper_add(i32 %t402, i32 %t403), !dbg !100
  store i32 %t404, ptr %slot68, !dbg !100
  br label %if.end.70, !dbg !100
if.else.72:
  br label %if.end.70, !dbg !100
if.end.70:
  br label %if.end.50, !dbg !100
if.else.52:
  br label %if.end.50, !dbg !100
if.end.50:
  %t405 = load i32, ptr %slot70, !dbg !101
  %t406 = icmp ugt i32 %t405, 63, !dbg !101
  br i1 %t406, label %if.then.76, label %if.else.77, !dbg !101
if.then.76:
  %t407 = getelementptr inbounds ptr, ptr %t1, i64 57, !dbg !102
  %rt.builder_null.408 = load ptr, ptr %t407, !invariant.load !8, !dbg !102
  call void %rt.builder_null.408(ptr %L, ptr %slot14, i64 1), !dbg !102
  br label %if.end.75, !dbg !102
if.else.77:
  %t409 = call i32 @ks_decode_aot_helper_u32(double 0x0000000000000000), !dbg !103
  %t410 = zext i32 %t409 to i64, !dbg !103
  %t411 = load i32, ptr %slot68, !dbg !103
  %t412 = zext i32 %t411 to i64, !dbg !103
  %t413 = getelementptr inbounds ptr, ptr %t1, i64 60, !dbg !103
  %rt.builder_string_scratch.414 = load ptr, ptr %t413, !invariant.load !8, !dbg !103
  call void %rt.builder_string_scratch.414(ptr %L, ptr %slot14, ptr %slot24, i64 %t410, i64 %t412, i64 1), !dbg !103
  br label %if.end.75, !dbg !103
if.end.75:
  %t415 = getelementptr inbounds ptr, ptr %t1, i64 65, !dbg !104
  %rt.builder_finish.416 = load ptr, ptr %t415, !invariant.load !8, !dbg !104
  call void %rt.builder_finish.416(ptr %L, ptr %slot14), !dbg !104
  ret i32 1, !dbg !104
}

define i32 @ks_register_07af12f296a4e582_4fbf2519c42b2677__neon(ptr %L) #0 {
entry:
  %slot6 = alloca i64, align 8
  br label %body
body:
  %t1 = call i32 @lua_checkstack(ptr %L, i32 4)
  %t2 = icmp eq i32 %t1, 0
  br i1 %t2, label %lua.raise.1, label %lua.ok.2, !prof !7
lua.raise.1:
  %t3 = call i32 (ptr, ptr, ...) @luaL_error(ptr %L, ptr @nupp.bytes.3, ptr @nupp.bytes.4) nomerge
  unreachable
lua.ok.2:
  %t4 = call i32 @lua_type(ptr %L, i32 1)
  %t5 = icmp eq i32 %t4, 4
  br i1 %t5, label %runtime.argument.3, label %runtime.lookup.4
runtime.argument.3:
  call void @lua_pushnil(ptr %L)
  call void @lua_pushvalue(ptr %L, i32 1)
  br label %runtime.found.5
runtime.lookup.4:
  call void @lua_getfield(ptr %L, i32 -10002, ptr @nupp.bytes.5)
  call void @lua_pushlstring(ptr %L, ptr @nupp.bytes.6, i64 19)
  call void @lua_call(ptr %L, i32 1, i32 1)
  call void @lua_getfield(ptr %L, i32 -1, ptr @nupp.bytes.7)
  call void @lua_call(ptr %L, i32 0, i32 1)
  br label %runtime.found.5
runtime.found.5:
  store i64 0, ptr %slot6
  %t7 = call ptr @lua_tolstring(ptr %L, i32 -1, ptr %slot6)
  %t8 = load i64, ptr %slot6
  %t9 = icmp eq ptr %t7, null
  %t10 = icmp ne i64 %t8, 8
  %t11 = or i1 %t9, %t10
  br i1 %t11, label %lua.raise.6, label %lua.ok.7, !prof !7
lua.raise.6:
  %t12 = call i32 (ptr, ptr, ...) @luaL_error(ptr %L, ptr @nupp.bytes.3, ptr @nupp.bytes.8) nomerge
  unreachable
lua.ok.7:
  %t13 = load ptr, ptr %t7, align 1
  %t14 = getelementptr inbounds ptr, ptr %t13, i64 0
  %t15 = load ptr, ptr %t14
  %t16 = ptrtoint ptr %t15 to i64
  %t17 = icmp ne i64 %t16, 1
  %t18 = getelementptr inbounds ptr, ptr %t13, i64 1
  %t19 = load ptr, ptr %t18
  %t20 = ptrtoint ptr %t19 to i64
  %t21 = icmp ugt i64 %t20, 4096
  %t22 = getelementptr inbounds ptr, ptr %t13, i64 2
  %t23 = load ptr, ptr %t22
  %t24 = ptrtoint ptr %t23 to i64
  %t25 = icmp ugt i64 %t24, 8256
  %t26 = getelementptr inbounds ptr, ptr %t13, i64 3
  %t27 = load ptr, ptr %t26
  %t28 = ptrtoint ptr %t27 to i64
  %t29 = icmp ne i64 %t28, ptrtoint (ptr getelementptr ({ ptr, i32, i32, i32, i32, [32 x i32] }, ptr null, i32 1) to i64)
  %t30 = getelementptr inbounds ptr, ptr %t13, i64 4
  %t31 = load ptr, ptr %t30
  %t32 = ptrtoint ptr %t31 to i64
  %t33 = icmp ne i64 %t32, ptrtoint (ptr getelementptr ({ ptr, i32, i32, i32, i32 }, ptr null, i32 1) to i64)
  %t34 = getelementptr inbounds ptr, ptr %t13, i64 5
  %t35 = load ptr, ptr %t34
  %t36 = ptrtoint ptr %t35 to i64
  %t37 = icmp ne i64 %t36, ptrtoint (ptr getelementptr ({ [10 x i32], i32, i32, i32, i32, i32, i32, ptr, [16 x { i32, i32, i32, i32, i32, i32, i32, i32, i64, i32, i32, i32, i32 }] }, ptr null, i32 0, i32 1) to i64)
  %t38 = getelementptr inbounds ptr, ptr %t13, i64 6
  %t39 = load ptr, ptr %t38
  %t40 = ptrtoint ptr %t39 to i64
  %t41 = icmp ne i64 %t40, ptrtoint (ptr getelementptr ({ [10 x i32], i32, i32, i32, i32, i32, i32, ptr, [16 x { i32, i32, i32, i32, i32, i32, i32, i32, i64, i32, i32, i32, i32 }] }, ptr null, i32 0, i32 7) to i64)
  %t42 = getelementptr inbounds ptr, ptr %t13, i64 7
  %t43 = load ptr, ptr %t42
  %t44 = ptrtoint ptr %t43 to i64
  %t45 = icmp ne i64 %t44, ptrtoint (ptr getelementptr ({ [10 x i32], i32, i32, i32, i32, i32, i32, ptr, [16 x { i32, i32, i32, i32, i32, i32, i32, i32, i64, i32, i32, i32, i32 }] }, ptr null, i32 0, i32 8) to i64)
  %t46 = getelementptr inbounds ptr, ptr %t13, i64 8
  %t47 = load ptr, ptr %t46
  %t48 = ptrtoint ptr %t47 to i64
  %t49 = icmp ne i64 %t48, ptrtoint (ptr getelementptr ({ i32, i32, i32, i32, i32, i32, i32, i32, i64, i32, i32, i32, i32 }, ptr null, i32 1) to i64)
  %t50 = getelementptr inbounds ptr, ptr %t13, i64 9
  %t51 = load ptr, ptr %t50
  %t52 = ptrtoint ptr %t51 to i64
  %t53 = icmp ne i64 %t52, ptrtoint (ptr getelementptr ({ i32, i32, i32, i32, i32, i32, i32, i32, i64, i32, i32, i32, i32 }, ptr null, i32 0, i32 2) to i64)
  %t54 = getelementptr inbounds ptr, ptr %t13, i64 10
  %t55 = load ptr, ptr %t54
  %t56 = ptrtoint ptr %t55 to i64
  %t57 = icmp ne i64 %t56, ptrtoint (ptr getelementptr ({ i32, i32, i32, i32, i32, i32, i32, i32, i64, i32, i32, i32, i32 }, ptr null, i32 0, i32 4) to i64)
  %t58 = or i1 %t17, %t21
  %t59 = or i1 %t58, %t25
  %t60 = or i1 %t59, %t29
  %t61 = or i1 %t60, %t33
  %t62 = or i1 %t61, %t37
  %t63 = or i1 %t62, %t41
  %t64 = or i1 %t63, %t45
  %t65 = or i1 %t64, %t49
  %t66 = or i1 %t65, %t53
  %t67 = or i1 %t66, %t57
  br i1 %t67, label %lua.raise.8, label %lua.ok.9, !prof !7
lua.raise.8:
  %t68 = call i32 (ptr, ptr, ...) @luaL_error(ptr %L, ptr @nupp.bytes.3, ptr @nupp.bytes.8) nomerge
  unreachable
lua.ok.9:
  store ptr %t13, ptr @ks.rt
  call void @lua_settop(ptr %L, i32 -3)
  call void @lua_createtable(ptr %L, i32 0, i32 2)
  call void @lua_pushlstring(ptr %L, ptr @nupp.bytes.9, i64 9)
  call void @lua_pushcclosure(ptr %L, ptr @ks_07af12f296a4e582_encode_aot__neon_lua, i32 0)
  call void @lua_rawset(ptr %L, i32 -3)
  call void @lua_pushlstring(ptr %L, ptr @nupp.bytes.10, i64 9)
  call void @lua_pushcclosure(ptr %L, ptr @ks_07af12f296a4e582_decode_aot__neon_lua, i32 0)
  call void @lua_rawset(ptr %L, i32 -3)
  ret i32 1
}

attributes #0 = { uwtable "probe-stack"="inline-asm" "frame-pointer"="non-leaf" }
attributes #1 = { alwaysinline nounwind uwtable "frame-pointer"="non-leaf" }
attributes #2 = { alwaysinline nounwind }
!llvm.dbg.cu = !{!1}
!llvm.module.flags = !{!2, !3}
!0 = !DIFile(filename: "base64.nupp", directory: "/private/tmp/nupp-codegen-experiment/src/nupp/codec")
!1 = distinct !DICompileUnit(language: DW_LANG_C11, file: !0, producer: "nupp", isOptimized: true, runtimeVersion: 0, emissionKind: LineTablesOnly)
!2 = !{i32 7, !"Dwarf Version", i32 4}
!3 = !{i32 2, !"Debug Info Version", i32 3}
!4 = !DISubroutineType(types: !{})
!5 = distinct !DISubprogram(name: "encodeAot", scope: !0, file: !0, line: 77, type: !4, scopeLine: 77, spFlags: DISPFlagDefinition | DISPFlagOptimized, unit: !1)
!6 = !DILocation(line: 77, column: 1, scope: !5)
!7 = !{!"branch_weights", i32 1, i32 1048575}
!8 = !{}
!9 = !DILocation(line: 77, column: 5, scope: !5)
!10 = !DILocation(line: 80, column: 5, scope: !5)
!11 = !DILocation(line: 81, column: 5, scope: !5)
!12 = !DILocation(line: 82, column: 5, scope: !5)
!13 = !DILocation(line: 84, column: 5, scope: !5)
!14 = !DILocation(line: 85, column: 5, scope: !5)
!15 = !DILocation(line: 86, column: 5, scope: !5)
!16 = !DILocation(line: 87, column: 9, scope: !5)
!17 = !DILocation(line: 88, column: 9, scope: !5)
!18 = !DILocation(line: 89, column: 9, scope: !5)
!19 = !DILocation(line: 90, column: 9, scope: !5)
!20 = !DILocation(line: 92, column: 9, scope: !5)
!21 = !DILocation(line: 93, column: 9, scope: !5)
!22 = !DILocation(line: 94, column: 9, scope: !5)
!23 = !DILocation(line: 95, column: 9, scope: !5)
!24 = !DILocation(line: 97, column: 9, scope: !5)
!25 = !DILocation(line: 111, column: 9, scope: !5)
!26 = !DILocation(line: 125, column: 9, scope: !5)
!27 = !DILocation(line: 139, column: 9, scope: !5)
!28 = !DILocation(line: 154, column: 9, scope: !5)
!29 = !DILocation(line: 155, column: 9, scope: !5)
!30 = !DILocation(line: 158, column: 5, scope: !5)
!31 = !DILocation(line: 159, column: 9, scope: !5)
!32 = !DILocation(line: 160, column: 9, scope: !5)
!33 = !DILocation(line: 161, column: 9, scope: !5)
!34 = !DILocation(line: 162, column: 9, scope: !5)
!35 = !DILocation(line: 163, column: 9, scope: !5)
!36 = !DILocation(line: 168, column: 9, scope: !5)
!37 = !DILocation(line: 173, column: 9, scope: !5)
!38 = !DILocation(line: 174, column: 9, scope: !5)
!39 = !DILocation(line: 175, column: 9, scope: !5)
!40 = !DILocation(line: 178, column: 5, scope: !5)
!41 = !DILocation(line: 179, column: 5, scope: !5)
!42 = !DILocation(line: 180, column: 9, scope: !5)
!43 = !DILocation(line: 181, column: 9, scope: !5)
!44 = !DILocation(line: 182, column: 9, scope: !5)
!45 = !DILocation(line: 187, column: 9, scope: !5)
!46 = !DILocation(line: 188, column: 9, scope: !5)
!47 = !DILocation(line: 189, column: 9, scope: !5)
!48 = !DILocation(line: 191, column: 9, scope: !5)
!49 = !DILocation(line: 192, column: 9, scope: !5)
!50 = !DILocation(line: 193, column: 9, scope: !5)
!51 = !DILocation(line: 194, column: 9, scope: !5)
!52 = !DILocation(line: 199, column: 9, scope: !5)
!53 = !DILocation(line: 204, column: 9, scope: !5)
!54 = !DILocation(line: 205, column: 9, scope: !5)
!55 = !DILocation(line: 208, column: 5, scope: !5)
!56 = !DILocation(line: 210, column: 5, scope: !5)
!57 = distinct !DISubprogram(name: "decodeAot", scope: !0, file: !0, line: 219, type: !4, scopeLine: 219, spFlags: DISPFlagDefinition | DISPFlagOptimized, unit: !1)
!58 = !DILocation(line: 219, column: 1, scope: !57)
!59 = !DILocation(line: 219, column: 5, scope: !57)
!60 = !DILocation(line: 220, column: 5, scope: !57)
!61 = !DILocation(line: 221, column: 5, scope: !57)
!62 = !DILocation(line: 223, column: 5, scope: !57)
!63 = !DILocation(line: 224, column: 5, scope: !57)
!64 = !DILocation(line: 225, column: 9, scope: !57)
!65 = !DILocation(line: 226, column: 13, scope: !57)
!66 = !DILocation(line: 230, column: 9, scope: !57)
!67 = !DILocation(line: 231, column: 13, scope: !57)
!68 = !DILocation(line: 235, column: 5, scope: !57)
!69 = !DILocation(line: 236, column: 5, scope: !57)
!70 = !DILocation(line: 237, column: 5, scope: !57)
!71 = !DILocation(line: 238, column: 5, scope: !57)
!72 = !DILocation(line: 239, column: 5, scope: !57)
!73 = !DILocation(line: 240, column: 9, scope: !57)
!74 = !DILocation(line: 242, column: 5, scope: !57)
!75 = !DILocation(line: 243, column: 9, scope: !57)
!76 = !DILocation(line: 244, column: 9, scope: !57)
!77 = !DILocation(line: 245, column: 9, scope: !57)
!78 = !DILocation(line: 246, column: 9, scope: !57)
!79 = !DILocation(line: 247, column: 9, scope: !57)
!80 = !DILocation(line: 248, column: 9, scope: !57)
!81 = !DILocation(line: 249, column: 9, scope: !57)
!82 = !DILocation(line: 250, column: 9, scope: !57)
!83 = !DILocation(line: 251, column: 9, scope: !57)
!84 = !DILocation(line: 252, column: 9, scope: !57)
!85 = !DILocation(line: 253, column: 9, scope: !57)
!86 = !DILocation(line: 256, column: 5, scope: !57)
!87 = !DILocation(line: 257, column: 9, scope: !57)
!88 = !DILocation(line: 258, column: 9, scope: !57)
!89 = !DILocation(line: 259, column: 9, scope: !57)
!90 = !DILocation(line: 260, column: 9, scope: !57)
!91 = !DILocation(line: 261, column: 13, scope: !57)
!92 = !DILocation(line: 264, column: 13, scope: !57)
!93 = !DILocation(line: 268, column: 13, scope: !57)
!94 = !DILocation(line: 270, column: 9, scope: !57)
!95 = !DILocation(line: 271, column: 9, scope: !57)
!96 = !DILocation(line: 272, column: 9, scope: !57)
!97 = !DILocation(line: 273, column: 9, scope: !57)
!98 = !DILocation(line: 274, column: 9, scope: !57)
!99 = !DILocation(line: 275, column: 13, scope: !57)
!100 = !DILocation(line: 276, column: 13, scope: !57)
!101 = !DILocation(line: 280, column: 5, scope: !57)
!102 = !DILocation(line: 281, column: 9, scope: !57)
!103 = !DILocation(line: 283, column: 9, scope: !57)
!104 = !DILocation(line: 286, column: 5, scope: !57)
