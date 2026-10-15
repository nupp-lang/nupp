@ks.rt = internal global ptr null
declare i32 @lua_checkstack(ptr, i32)
declare i32 @lua_type(ptr, i32)
declare ptr @luaL_checklstring(ptr, i32, ptr)
declare void @lua_pushvalue(ptr, i32)
define internal i32 @nupp.wrap.u32(double %v) #2 {
  %shifted = fadd double %v, 0x4338000000000000
  %bits = bitcast double %shifted to i64
  %out = trunc i64 %bits to i32
  ret i32 %out
}
declare void @lua_pushnumber(ptr, double)
@ks.key.ks_db5c9457e129530e___nupp_const_decode_fused_24f677cbe166e03f__5f5f6e757070436f6e73745f6465636f646546757365645f32346636373763626531363665303366.v2_tape = internal global i8 0
declare i64 @llvm.fptosi.sat.i64.f64(double)
declare i64 @llvm.fptoui.sat.i64.f64(double)
declare <4 x i32> @llvm.aarch64.neon.umaxp.v4i32(<4 x i32>, <4 x i32>)
declare <16 x i8> @llvm.aarch64.neon.tbl1.v16i8(<16 x i8>, <16 x i8>)
declare i32 @llvm.aarch64.neon.umaxv.i32.v16i8(<16 x i8>)
declare i64 @llvm.cttz.i64(i64, i1)
@ks.key.ks_db5c9457e129530e___nupp_const_decode_fused_a640dbc37ebbc1be__5f5f6e757070436f6e73745f6465636f646546757365645f61363430646263333765626263316265.v2_tape = internal global i8 0
@ks.key.ks_db5c9457e129530e___nupp_const_decode_fused_f007fffb3d50ef9f__5f5f6e757070436f6e73745f6465636f646546757365645f66303037666666623364353065663966.v2_tape = internal global i8 0
@nupp.bytes.1 = private unnamed_addr constant [3 x i8] c"%s\00", align 1
@nupp.bytes.2 = private unnamed_addr constant [32 x i8] c"AOT builder Lua stack exhausted\00", align 1
declare i32 @luaL_error(ptr, ptr, ...)
declare void @lua_pushnil(ptr)
@nupp.bytes.3 = private unnamed_addr constant [8 x i8] c"require\00", align 1
declare void @lua_getfield(ptr, i32, ptr)
@nupp.bytes.4 = private unnamed_addr constant [19 x i8] c"nupp.runtime.native", align 1
declare void @lua_pushlstring(ptr, ptr, i64)
declare void @lua_call(ptr, i32, i32)
@nupp.bytes.5 = private unnamed_addr constant [11 x i8] c"aotRuntime\00", align 1
declare ptr @lua_tolstring(ptr, i32, ptr)
@nupp.bytes.6 = private unnamed_addr constant [56 x i8] c"AOT runtime is not the one this module was compiled for\00", align 1
declare void @lua_settop(ptr, i32)
declare void @lua_createtable(ptr, i32, i32)
@nupp.bytes.7 = private unnamed_addr constant [40 x i8] c"__nuppConst_decodeFused_24f677cbe166e03f", align 1
declare void @lua_pushcclosure(ptr, ptr, i32)
declare void @lua_rawset(ptr, i32)
@nupp.bytes.8 = private unnamed_addr constant [40 x i8] c"__nuppConst_decodeFused_a640dbc37ebbc1be", align 1
@nupp.bytes.9 = private unnamed_addr constant [40 x i8] c"__nuppConst_decodeFused_f007fffb3d50ef9f", align 1

define internal <16 x i8> @ks___nupp_const_decode_fused_24f677cbe166e03f__5f5f6e757070436f6e73745f6465636f646546757365645f32346636373763626531363665303366_helper_nibble_table(<16 x i8> %h_a_zero, i32 %h_a_e0, i32 %h_a_e1, i32 %h_a_e2, i32 %h_a_e3, i32 %h_a_e4, i32 %h_a_e5, i32 %h_a_e6, i32 %h_a_e7, i32 %h_a_e8, i32 %h_a_e9, i32 %h_a_e10, i32 %h_a_e11, i32 %h_a_e12, i32 %h_a_e13, i32 %h_a_e14, i32 %h_a_e15) #1 {
entry:
  br label %body
body:
  %t1 = trunc i32 %h_a_e0 to i8
  %t2 = insertelement <16 x i8> %h_a_zero, i8 %t1, i32 0
  %t3 = trunc i32 %h_a_e1 to i8
  %t4 = insertelement <16 x i8> %t2, i8 %t3, i32 1
  %t5 = trunc i32 %h_a_e2 to i8
  %t6 = insertelement <16 x i8> %t4, i8 %t5, i32 2
  %t7 = trunc i32 %h_a_e3 to i8
  %t8 = insertelement <16 x i8> %t6, i8 %t7, i32 3
  %t9 = trunc i32 %h_a_e4 to i8
  %t10 = insertelement <16 x i8> %t8, i8 %t9, i32 4
  %t11 = trunc i32 %h_a_e5 to i8
  %t12 = insertelement <16 x i8> %t10, i8 %t11, i32 5
  %t13 = trunc i32 %h_a_e6 to i8
  %t14 = insertelement <16 x i8> %t12, i8 %t13, i32 6
  %t15 = trunc i32 %h_a_e7 to i8
  %t16 = insertelement <16 x i8> %t14, i8 %t15, i32 7
  %t17 = trunc i32 %h_a_e8 to i8
  %t18 = insertelement <16 x i8> %t16, i8 %t17, i32 8
  %t19 = trunc i32 %h_a_e9 to i8
  %t20 = insertelement <16 x i8> %t18, i8 %t19, i32 9
  %t21 = trunc i32 %h_a_e10 to i8
  %t22 = insertelement <16 x i8> %t20, i8 %t21, i32 10
  %t23 = trunc i32 %h_a_e11 to i8
  %t24 = insertelement <16 x i8> %t22, i8 %t23, i32 11
  %t25 = trunc i32 %h_a_e12 to i8
  %t26 = insertelement <16 x i8> %t24, i8 %t25, i32 12
  %t27 = trunc i32 %h_a_e13 to i8
  %t28 = insertelement <16 x i8> %t26, i8 %t27, i32 13
  %t29 = trunc i32 %h_a_e14 to i8
  %t30 = insertelement <16 x i8> %t28, i8 %t29, i32 14
  %t31 = trunc i32 %h_a_e15 to i8
  %t32 = insertelement <16 x i8> %t30, i8 %t31, i32 15
  ret <16 x i8> %t32
}

define internal i32 @ks_db5c9457e129530e___nupp_const_decode_fused_24f677cbe166e03f__5f5f6e757070436f6e73745f6465636f646546757365645f32346636373763626531363665303366__neon_lua(ptr %L) #0 !dbg !5 {
entry:
  %slot6 = alloca i64, align 8
  %slot7 = alloca ptr, align 8
  %slot20 = alloca i32, align 4
  %slot27 = alloca { ptr, i32, i32, i32, i32, [32 x i32] }, align 8
  %slot33 = alloca i32, align 4
  %slot35 = alloca i32, align 4
  %slot36 = alloca i1, align 4
  %slot37 = alloca i1, align 4
  %slot38 = alloca i1, align 4
  %slot39 = alloca i1, align 4
  %slot41 = alloca i32, align 4
  %slot43 = alloca i32, align 4
  %slot45 = alloca i32, align 4
  %slot46 = alloca i1, align 4
  %slot48 = alloca i32, align 4
  %slot49 = alloca i1, align 4
  %slot50 = alloca i1, align 4
  %slot55 = alloca i64, align 8
  %slot56 = alloca i1, align 4
  %slot68 = alloca i64, align 8
  %slot70 = alloca i32, align 4
  %slot168 = alloca <16 x i8>
  %slot196 = alloca <16 x i1>
  %slot210 = alloca <16 x i1>
  %slot224 = alloca <16 x i1>
  %slot237 = alloca <16 x i1>
  %slot238 = alloca i1, align 4
  %slot249 = alloca <16 x i1>
  %slot357 = alloca <16 x i8>
  %slot361 = alloca <16 x i8>
  %slot365 = alloca <16 x i8>
  %slot369 = alloca <16 x i8>
  %slot374 = alloca <16 x i8>
  %slot377 = alloca <16 x i8>
  %slot380 = alloca <16 x i8>
  %slot383 = alloca <16 x i8>
  %slot430 = alloca <16 x i8>
  %slot453 = alloca <16 x i8>
  %slot482 = alloca i32, align 4
  %slot483 = alloca i1, align 4
  %slot502 = alloca i32, align 4
  %slot520 = alloca i32, align 4
  %slot562 = alloca i32, align 4
  %slot603 = alloca i32, align 4
  %slot615 = alloca i32, align 4
  %slot624 = alloca i32, align 4
  %slot644 = alloca i1, align 4
  %slot677 = alloca i1, align 4
  %slot752 = alloca i1, align 4
  %slot760 = alloca i32, align 4
  %slot812 = alloca i1, align 4
  %slot1614 = alloca i32, align 4
  %slot1618 = alloca [4096 x i8], align 16
  %slot1629 = alloca i32, align 4
  %slot1633 = alloca i32, align 4
  %slot1634 = alloca i1, align 4
  %slot1635 = alloca i1, align 4
  %slot1637 = alloca i32, align 4
  %slot1640 = alloca i1, align 4
  %slot1675 = alloca i32, align 4
  %slot1677 = alloca i32, align 4
  %slot1679 = alloca i32, align 4
  %slot1681 = alloca i32, align 4
  %slot1683 = alloca i32, align 4
  %slot1685 = alloca i32, align 4
  %slot1698 = alloca i32, align 4
  %slot1723 = alloca i32, align 4
  %slot1726 = alloca i32, align 4
  %slot1791 = alloca i32, align 4
  %slot1797 = alloca i32, align 4
  %slot1806 = alloca i32, align 4
  %slot1808 = alloca i32, align 4
  %slot1809 = alloca i32, align 4
  %slot1842 = alloca i32, align 4
  %slot1848 = alloca i32, align 4
  %slot1857 = alloca i32, align 4
  %slot1859 = alloca i32, align 4
  %slot1860 = alloca i32, align 4
  %slot1896 = alloca i32, align 4
  %slot1902 = alloca i32, align 4
  %slot1911 = alloca i32, align 4
  %slot1913 = alloca i32, align 4
  %slot1914 = alloca i32, align 4
  %slot1957 = alloca i32, align 4
  %slot2033 = alloca i32, align 4
  %slot2050 = alloca i32, align 4
  %slot2052 = alloca i32, align 4
  %slot2055 = alloca i32, align 4
  %slot2059 = alloca i1, align 4
  %slot2071 = alloca i1, align 4
  %slot2137 = alloca i1, align 4
  %slot2148 = alloca i32, align 4
  %slot2181 = alloca i32, align 4
  %slot2220 = alloca i32, align 4
  %slot2223 = alloca i32, align 4
  %slot2227 = alloca i1, align 4
  %slot2232 = alloca i32, align 4
  %slot2236 = alloca i32, align 4
  %slot2247 = alloca i1, align 4
  %slot2258 = alloca i32, align 4
  br label %body
body:
  %t1 = load ptr, ptr @ks.rt, !dbg !6
  %t2 = call i32 @lua_checkstack(ptr %L, i32 10), !dbg !6
  %t3 = icmp eq i32 %t2, 0, !dbg !6
  br i1 %t3, label %lua.raise.1, label %lua.ok.2, !prof !7, !dbg !6
lua.raise.1:
  %t4 = getelementptr inbounds ptr, ptr %t1, i64 11, !dbg !6
  %rt.raise.5 = load ptr, ptr %t4, !invariant.load !8, !dbg !6
  call void %rt.raise.5(ptr %L, i64 1) nomerge, !dbg !6
  unreachable, !dbg !6
lua.ok.2:
  %t8 = call i32 @lua_type(ptr %L, i32 1), !dbg !6
  %t9 = icmp eq i32 %t8, 4, !dbg !6
  br i1 %t9, label %lua.string.3, label %lua.buffer.4, !dbg !6
lua.string.3:
  %t10 = call ptr @luaL_checklstring(ptr %L, i32 1, ptr %slot6), !dbg !6
  store ptr %t10, ptr %slot7, !dbg !6
  br label %lua.bytes.5, !dbg !6
lua.buffer.4:
  %t11 = getelementptr inbounds ptr, ptr %t1, i64 14, !dbg !6
  %rt.bytes.12 = load ptr, ptr %t11, !invariant.load !8, !dbg !6
  %t13 = call ptr %rt.bytes.12(ptr %L, i64 1, ptr %slot6), !dbg !6
  store ptr %t13, ptr %slot7, !dbg !6
  br label %lua.bytes.5, !dbg !6
lua.bytes.5:
  %t14 = load ptr, ptr %slot7, !dbg !6
  %t15 = load i64, ptr %slot6, !dbg !6
  %t16 = icmp ugt i64 %t15, 4294967295, !dbg !9
  br i1 %t16, label %lua.raise.6, label %lua.ok.7, !prof !7, !dbg !9
lua.raise.6:
  %t17 = getelementptr inbounds ptr, ptr %t1, i64 11, !dbg !9
  %rt.raise.18 = load ptr, ptr %t17, !invariant.load !8, !dbg !9
  call void %rt.raise.18(ptr %L, i64 2) nomerge, !dbg !9
  unreachable, !dbg !9
lua.ok.7:
  %t19 = trunc i64 %t15 to i32, !dbg !9
  store i32 %t19, ptr %slot20, !dbg !9
  %t21 = load i32, ptr %slot20, !dbg !10
  %t22 = icmp ult i32 2147483647, %t21, !dbg !10
  br i1 %t22, label %if.then.9, label %if.else.10, !dbg !10
if.then.9:
  call void @lua_pushvalue(ptr %L, i32 2), !dbg !11
  %t23 = call i32 @nupp.wrap.u32(double 0x4014000000000000), !dbg !11
  %t24 = uitofp i32 %t23 to double, !dbg !11
  call void @lua_pushnumber(ptr %L, double %t24), !dbg !11
  %t25 = call i32 @nupp.wrap.u32(double 0x3FF0000000000000), !dbg !11
  %t26 = uitofp i32 %t25 to double, !dbg !11
  call void @lua_pushnumber(ptr %L, double %t26), !dbg !11
  ret i32 3, !dbg !11
if.else.10:
  br label %if.end.8, !dbg !11
if.end.8:
  %t28 = load i32, ptr %slot20, !dbg !12
  %t29 = zext i32 %t28 to i64, !dbg !12
  %t30 = getelementptr inbounds ptr, ptr %t1, i64 29, !dbg !12
  %rt.scratch_u32.31 = load ptr, ptr %t30, !invariant.load !8, !dbg !12
  call void %rt.scratch_u32.31(ptr %L, ptr %slot27, i64 %t29, ptr @ks.key.ks_db5c9457e129530e___nupp_const_decode_fused_24f677cbe166e03f__5f5f6e757070436f6e73745f6465636f646546757365645f32346636373763626531363665303366.v2_tape), !dbg !12
  %t32 = call i32 @nupp.wrap.u32(double 0x0000000000000000), !dbg !13
  store i32 %t32, ptr %slot33, !dbg !13
  %t34 = call i32 @nupp.wrap.u32(double 0x0000000000000000), !dbg !14
  store i32 %t34, ptr %slot35, !dbg !14
  store i1 false, ptr %slot36, !dbg !15
  store i1 false, ptr %slot37, !dbg !16
  store i1 false, ptr %slot38, !dbg !17
  store i1 false, ptr %slot39, !dbg !18
  %t40 = call i32 @nupp.wrap.u32(double 0x0000000000000000), !dbg !19
  store i32 %t40, ptr %slot41, !dbg !19
  %t42 = call i32 @nupp.wrap.u32(double 0x0000000000000000), !dbg !20
  store i32 %t42, ptr %slot43, !dbg !20
  %t44 = call i32 @nupp.wrap.u32(double 0x0000000000000000), !dbg !21
  store i32 %t44, ptr %slot45, !dbg !21
  store i1 false, ptr %slot46, !dbg !22
  %t47 = call i32 @nupp.wrap.u32(double 0x0000000000000000), !dbg !23
  store i32 %t47, ptr %slot48, !dbg !23
  store i1 false, ptr %slot49, !dbg !24
  store i1 false, ptr %slot50, !dbg !25
  %t51 = call i64 @llvm.fptosi.sat.i64.f64(double 0x3FF0000000000000), !dbg !26
  %t52 = call i64 @llvm.fptoui.sat.i64.f64(double 0x3FF0000000000000), !dbg !26
  %t53 = fcmp olt double 0x3FF0000000000000, 0.0, !dbg !26
  %t54 = select i1 %t53, i64 %t51, i64 %t52, !dbg !26
  store i64 %t54, ptr %slot55, !dbg !26
  store i1 false, ptr %slot56, !dbg !27
  %t57 = icmp ule i64 %t15, 4294967295, !dbg !28
  br i1 %t57, label %cursors.wide.11, label %cursors.narrow.12, !dbg !28
cursors.wide.11:
  br label %while.head.14, !dbg !28
while.head.14:
  %t58 = load i32, ptr %slot33, !dbg !28
  %t59 = load i32, ptr %slot20, !dbg !28
  %t60 = icmp ult i32 %t58, %t59, !dbg !28
  br i1 %t60, label %or.end.18, label %or.rhs.17, !dbg !28
or.rhs.17:
  %t61 = load i1, ptr %slot49, !dbg !28
  %t62 = xor i1 %t61, true, !dbg !28
  br label %or.end.18, !dbg !28
or.end.18:
  %t63 = phi i1 [ true, %while.head.14 ], [ %t62, %or.rhs.17 ], !dbg !28
  br i1 %t63, label %while.body.15, label %while.end.16, !dbg !28
while.body.15:
  %t64 = call i64 @llvm.fptosi.sat.i64.f64(double 0x0000000000000000), !dbg !29
  %t65 = call i64 @llvm.fptoui.sat.i64.f64(double 0x0000000000000000), !dbg !29
  %t66 = fcmp olt double 0x0000000000000000, 0.0, !dbg !29
  %t67 = select i1 %t66, i64 %t64, i64 %t65, !dbg !29
  store i64 %t67, ptr %slot68, !dbg !29
  %t69 = call i32 @nupp.wrap.u32(double 0x0000000000000000), !dbg !30
  store i32 %t69, ptr %slot70, !dbg !30
  br i1 true, label %if.then.20, label %if.else.21, !dbg !31
if.then.20:
  %t71 = load i1, ptr %slot56, !dbg !32
  %t72 = xor i1 %t71, true, !dbg !32
  br i1 %t72, label %and.rhs.23, label %and.end.24, !dbg !32
and.rhs.23:
  %t73 = load i32, ptr %slot33, !dbg !32
  %t74 = zext i32 %t73 to i64, !dbg !32
  %t75 = zext i32 16 to i64, !dbg !32
  %t76 = add i64 %t74, %t75, !dbg !32
  %t77 = load i32, ptr %slot20, !dbg !32
  %t78 = zext i32 %t77 to i64, !dbg !32
  %t79 = icmp ule i64 %t76, %t78, !dbg !32
  br label %and.end.24, !dbg !32
and.end.24:
  %t80 = phi i1 [ false, %if.then.20 ], [ %t79, %and.rhs.23 ], !dbg !32
  br i1 %t80, label %if.then.25, label %if.else.26, !dbg !32
if.then.25:
  %t81 = load i32, ptr %slot33, !dbg !33
  %t82 = zext i32 %t81 to i64, !dbg !33
  %t83 = add nuw i64 %t82, 0, !dbg !33
  %t84 = getelementptr inbounds nuw i8, ptr %t14, i64 %t83, !dbg !33
  br i1 true, label %simd.yes.27, label %simd.no.28, !dbg !33
simd.yes.27:
  %t85 = load <16 x i8>, ptr %t84, align 1, !dbg !33
  br label %simd.join.29, !dbg !33
simd.no.28:
  %t86 = load i32, ptr %slot33, !dbg !33
  %t87 = add i32 %t86, 1, !dbg !33
  %t88 = zext i32 %t87 to i64, !dbg !33
  %t89 = icmp ne i64 %t88, 0, !dbg !33
  %t90 = sub i64 %t88, 1, !dbg !33
  %t91 = select i1 %t89, i64 %t90, i64 -1, !dbg !33
  %t92 = icmp ult i64 %t91, %t15, !dbg !33
  %t93 = sub i64 %t15, %t91, !dbg !33
  %t94 = icmp ult i64 %t93, 16, !dbg !33
  %t95 = select i1 %t94, i64 %t93, i64 16, !dbg !33
  %t96 = select i1 %t92, i64 %t95, i64 0, !dbg !33
  %t97 = trunc i64 %t96 to i32, !dbg !33
  %t98 = select i1 %t92, i64 %t91, i64 0, !dbg !33
  %t99 = getelementptr inbounds i8, ptr %t14, i64 %t98, !dbg !33
  %t100 = icmp eq i32 %t97, 16, !dbg !33
  br i1 %t100, label %simd.yes.30, label %simd.no.31, !dbg !33
simd.yes.30:
  %t101 = load <16 x i8>, ptr %t99, align 1, !dbg !33
  br label %simd.join.32, !dbg !33
simd.no.31:
  switch i32 %t97, label %tail.done.49 [ i32 1, label %tail.lane.33 i32 2, label %tail.lane.34 i32 3, label %tail.lane.35 i32 4, label %tail.lane.36 i32 5, label %tail.lane.37 i32 6, label %tail.lane.38 i32 7, label %tail.lane.39 i32 8, label %tail.lane.40 i32 9, label %tail.lane.41 i32 10, label %tail.lane.42 i32 11, label %tail.lane.43 i32 12, label %tail.lane.44 i32 13, label %tail.lane.45 i32 14, label %tail.lane.46 i32 15, label %tail.lane.47 i32 16, label %tail.lane.48 ], !dbg !33
tail.lane.48:
  %t102 = getelementptr inbounds i8, ptr %t99, i64 15, !dbg !33
  %t103 = load i8, ptr %t102, align 1, !dbg !33
  %t104 = insertelement <16 x i8> zeroinitializer, i8 %t103, i32 15, !dbg !33
  br label %tail.lane.47, !dbg !33
tail.lane.47:
  %t105 = phi <16 x i8> [ zeroinitializer, %simd.no.31 ], [ %t104, %tail.lane.48 ], !dbg !33
  %t106 = getelementptr inbounds i8, ptr %t99, i64 14, !dbg !33
  %t107 = load i8, ptr %t106, align 1, !dbg !33
  %t108 = insertelement <16 x i8> %t105, i8 %t107, i32 14, !dbg !33
  br label %tail.lane.46, !dbg !33
tail.lane.46:
  %t109 = phi <16 x i8> [ zeroinitializer, %simd.no.31 ], [ %t108, %tail.lane.47 ], !dbg !33
  %t110 = getelementptr inbounds i8, ptr %t99, i64 13, !dbg !33
  %t111 = load i8, ptr %t110, align 1, !dbg !33
  %t112 = insertelement <16 x i8> %t109, i8 %t111, i32 13, !dbg !33
  br label %tail.lane.45, !dbg !33
tail.lane.45:
  %t113 = phi <16 x i8> [ zeroinitializer, %simd.no.31 ], [ %t112, %tail.lane.46 ], !dbg !33
  %t114 = getelementptr inbounds i8, ptr %t99, i64 12, !dbg !33
  %t115 = load i8, ptr %t114, align 1, !dbg !33
  %t116 = insertelement <16 x i8> %t113, i8 %t115, i32 12, !dbg !33
  br label %tail.lane.44, !dbg !33
tail.lane.44:
  %t117 = phi <16 x i8> [ zeroinitializer, %simd.no.31 ], [ %t116, %tail.lane.45 ], !dbg !33
  %t118 = getelementptr inbounds i8, ptr %t99, i64 11, !dbg !33
  %t119 = load i8, ptr %t118, align 1, !dbg !33
  %t120 = insertelement <16 x i8> %t117, i8 %t119, i32 11, !dbg !33
  br label %tail.lane.43, !dbg !33
tail.lane.43:
  %t121 = phi <16 x i8> [ zeroinitializer, %simd.no.31 ], [ %t120, %tail.lane.44 ], !dbg !33
  %t122 = getelementptr inbounds i8, ptr %t99, i64 10, !dbg !33
  %t123 = load i8, ptr %t122, align 1, !dbg !33
  %t124 = insertelement <16 x i8> %t121, i8 %t123, i32 10, !dbg !33
  br label %tail.lane.42, !dbg !33
tail.lane.42:
  %t125 = phi <16 x i8> [ zeroinitializer, %simd.no.31 ], [ %t124, %tail.lane.43 ], !dbg !33
  %t126 = getelementptr inbounds i8, ptr %t99, i64 9, !dbg !33
  %t127 = load i8, ptr %t126, align 1, !dbg !33
  %t128 = insertelement <16 x i8> %t125, i8 %t127, i32 9, !dbg !33
  br label %tail.lane.41, !dbg !33
tail.lane.41:
  %t129 = phi <16 x i8> [ zeroinitializer, %simd.no.31 ], [ %t128, %tail.lane.42 ], !dbg !33
  %t130 = getelementptr inbounds i8, ptr %t99, i64 8, !dbg !33
  %t131 = load i8, ptr %t130, align 1, !dbg !33
  %t132 = insertelement <16 x i8> %t129, i8 %t131, i32 8, !dbg !33
  br label %tail.lane.40, !dbg !33
tail.lane.40:
  %t133 = phi <16 x i8> [ zeroinitializer, %simd.no.31 ], [ %t132, %tail.lane.41 ], !dbg !33
  %t134 = getelementptr inbounds i8, ptr %t99, i64 7, !dbg !33
  %t135 = load i8, ptr %t134, align 1, !dbg !33
  %t136 = insertelement <16 x i8> %t133, i8 %t135, i32 7, !dbg !33
  br label %tail.lane.39, !dbg !33
tail.lane.39:
  %t137 = phi <16 x i8> [ zeroinitializer, %simd.no.31 ], [ %t136, %tail.lane.40 ], !dbg !33
  %t138 = getelementptr inbounds i8, ptr %t99, i64 6, !dbg !33
  %t139 = load i8, ptr %t138, align 1, !dbg !33
  %t140 = insertelement <16 x i8> %t137, i8 %t139, i32 6, !dbg !33
  br label %tail.lane.38, !dbg !33
tail.lane.38:
  %t141 = phi <16 x i8> [ zeroinitializer, %simd.no.31 ], [ %t140, %tail.lane.39 ], !dbg !33
  %t142 = getelementptr inbounds i8, ptr %t99, i64 5, !dbg !33
  %t143 = load i8, ptr %t142, align 1, !dbg !33
  %t144 = insertelement <16 x i8> %t141, i8 %t143, i32 5, !dbg !33
  br label %tail.lane.37, !dbg !33
tail.lane.37:
  %t145 = phi <16 x i8> [ zeroinitializer, %simd.no.31 ], [ %t144, %tail.lane.38 ], !dbg !33
  %t146 = getelementptr inbounds i8, ptr %t99, i64 4, !dbg !33
  %t147 = load i8, ptr %t146, align 1, !dbg !33
  %t148 = insertelement <16 x i8> %t145, i8 %t147, i32 4, !dbg !33
  br label %tail.lane.36, !dbg !33
tail.lane.36:
  %t149 = phi <16 x i8> [ zeroinitializer, %simd.no.31 ], [ %t148, %tail.lane.37 ], !dbg !33
  %t150 = getelementptr inbounds i8, ptr %t99, i64 3, !dbg !33
  %t151 = load i8, ptr %t150, align 1, !dbg !33
  %t152 = insertelement <16 x i8> %t149, i8 %t151, i32 3, !dbg !33
  br label %tail.lane.35, !dbg !33
tail.lane.35:
  %t153 = phi <16 x i8> [ zeroinitializer, %simd.no.31 ], [ %t152, %tail.lane.36 ], !dbg !33
  %t154 = getelementptr inbounds i8, ptr %t99, i64 2, !dbg !33
  %t155 = load i8, ptr %t154, align 1, !dbg !33
  %t156 = insertelement <16 x i8> %t153, i8 %t155, i32 2, !dbg !33
  br label %tail.lane.34, !dbg !33
tail.lane.34:
  %t157 = phi <16 x i8> [ zeroinitializer, %simd.no.31 ], [ %t156, %tail.lane.35 ], !dbg !33
  %t158 = getelementptr inbounds i8, ptr %t99, i64 1, !dbg !33
  %t159 = load i8, ptr %t158, align 1, !dbg !33
  %t160 = insertelement <16 x i8> %t157, i8 %t159, i32 1, !dbg !33
  br label %tail.lane.33, !dbg !33
tail.lane.33:
  %t161 = phi <16 x i8> [ zeroinitializer, %simd.no.31 ], [ %t160, %tail.lane.34 ], !dbg !33
  %t162 = getelementptr inbounds i8, ptr %t99, i64 0, !dbg !33
  %t163 = load i8, ptr %t162, align 1, !dbg !33
  %t164 = insertelement <16 x i8> %t161, i8 %t163, i32 0, !dbg !33
  br label %tail.done.49, !dbg !33
tail.done.49:
  %t165 = phi <16 x i8> [ zeroinitializer, %simd.no.31 ], [ %t164, %tail.lane.33 ], !dbg !33
  br label %simd.join.32, !dbg !33
simd.join.32:
  %t166 = phi <16 x i8> [ %t101, %simd.yes.30 ], [ %t165, %tail.done.49 ], !dbg !33
  br label %simd.join.29, !dbg !33
simd.join.29:
  %t167 = phi <16 x i8> [ %t85, %simd.yes.27 ], [ %t166, %simd.join.32 ], !dbg !33
  store <16 x i8> %t167, ptr %slot168, !dbg !33
  %t169 = load <16 x i8>, ptr %slot168, !dbg !34
  %t170 = call i32 @nupp.wrap.u32(double 0x405EC00000000000), !dbg !34
  %t171 = trunc i32 %t170 to i8, !dbg !34
  %t172 = insertelement <16 x i8> poison, i8 %t171, i64 0, !dbg !34
  %t173 = shufflevector <16 x i8> %t172, <16 x i8> poison, <16 x i32> zeroinitializer, !dbg !34
  %t174 = icmp eq <16 x i8> %t169, %t173, !dbg !34
  %t175 = load <16 x i8>, ptr %slot168, !dbg !34
  %t176 = call i32 @nupp.wrap.u32(double 0x405F400000000000), !dbg !34
  %t177 = trunc i32 %t176 to i8, !dbg !34
  %t178 = insertelement <16 x i8> poison, i8 %t177, i64 0, !dbg !34
  %t179 = shufflevector <16 x i8> %t178, <16 x i8> poison, <16 x i32> zeroinitializer, !dbg !34
  %t180 = icmp eq <16 x i8> %t175, %t179, !dbg !34
  %t181 = or <16 x i1> %t174, %t180, !dbg !34
  %t182 = load <16 x i8>, ptr %slot168, !dbg !34
  %t183 = call i32 @nupp.wrap.u32(double 0x4056C00000000000), !dbg !34
  %t184 = trunc i32 %t183 to i8, !dbg !34
  %t185 = insertelement <16 x i8> poison, i8 %t184, i64 0, !dbg !34
  %t186 = shufflevector <16 x i8> %t185, <16 x i8> poison, <16 x i32> zeroinitializer, !dbg !34
  %t187 = icmp eq <16 x i8> %t182, %t186, !dbg !34
  %t188 = or <16 x i1> %t181, %t187, !dbg !34
  %t189 = load <16 x i8>, ptr %slot168, !dbg !34
  %t190 = call i32 @nupp.wrap.u32(double 0x4057400000000000), !dbg !34
  %t191 = trunc i32 %t190 to i8, !dbg !34
  %t192 = insertelement <16 x i8> poison, i8 %t191, i64 0, !dbg !34
  %t193 = shufflevector <16 x i8> %t192, <16 x i8> poison, <16 x i32> zeroinitializer, !dbg !34
  %t194 = icmp eq <16 x i8> %t189, %t193, !dbg !34
  %t195 = or <16 x i1> %t188, %t194, !dbg !34
  store <16 x i1> %t195, ptr %slot196, !dbg !34
  %t197 = load <16 x i8>, ptr %slot168, !dbg !35
  %t198 = call i32 @nupp.wrap.u32(double 0x404D000000000000), !dbg !35
  %t199 = trunc i32 %t198 to i8, !dbg !35
  %t200 = insertelement <16 x i8> poison, i8 %t199, i64 0, !dbg !35
  %t201 = shufflevector <16 x i8> %t200, <16 x i8> poison, <16 x i32> zeroinitializer, !dbg !35
  %t202 = icmp eq <16 x i8> %t197, %t201, !dbg !35
  %t203 = load <16 x i8>, ptr %slot168, !dbg !35
  %t204 = call i32 @nupp.wrap.u32(double 0x4046000000000000), !dbg !35
  %t205 = trunc i32 %t204 to i8, !dbg !35
  %t206 = insertelement <16 x i8> poison, i8 %t205, i64 0, !dbg !35
  %t207 = shufflevector <16 x i8> %t206, <16 x i8> poison, <16 x i32> zeroinitializer, !dbg !35
  %t208 = icmp eq <16 x i8> %t203, %t207, !dbg !35
  %t209 = or <16 x i1> %t202, %t208, !dbg !35
  store <16 x i1> %t209, ptr %slot210, !dbg !35
  %t211 = load <16 x i8>, ptr %slot168, !dbg !36
  %t212 = call i32 @nupp.wrap.u32(double 0x4041000000000000), !dbg !36
  %t213 = trunc i32 %t212 to i8, !dbg !36
  %t214 = insertelement <16 x i8> poison, i8 %t213, i64 0, !dbg !36
  %t215 = shufflevector <16 x i8> %t214, <16 x i8> poison, <16 x i32> zeroinitializer, !dbg !36
  %t216 = icmp eq <16 x i8> %t211, %t215, !dbg !36
  %t217 = load <16 x i8>, ptr %slot168, !dbg !36
  %t218 = call i32 @nupp.wrap.u32(double 0x4057000000000000), !dbg !36
  %t219 = trunc i32 %t218 to i8, !dbg !36
  %t220 = insertelement <16 x i8> poison, i8 %t219, i64 0, !dbg !36
  %t221 = shufflevector <16 x i8> %t220, <16 x i8> poison, <16 x i32> zeroinitializer, !dbg !36
  %t222 = icmp eq <16 x i8> %t217, %t221, !dbg !36
  %t223 = or <16 x i1> %t216, %t222, !dbg !36
  store <16 x i1> %t223, ptr %slot224, !dbg !36
  %t225 = load <16 x i1>, ptr %slot196, !dbg !37
  %t226 = load <16 x i1>, ptr %slot210, !dbg !37
  %t227 = or <16 x i1> %t225, %t226, !dbg !37
  %t228 = load <16 x i1>, ptr %slot224, !dbg !37
  %t229 = or <16 x i1> %t227, %t228, !dbg !37
  %t230 = load <16 x i8>, ptr %slot168, !dbg !37
  %t231 = call i32 @nupp.wrap.u32(double 0x4040000000000000), !dbg !37
  %t232 = trunc i32 %t231 to i8, !dbg !37
  %t233 = insertelement <16 x i8> poison, i8 %t232, i64 0, !dbg !37
  %t234 = shufflevector <16 x i8> %t233, <16 x i8> poison, <16 x i32> zeroinitializer, !dbg !37
  %t235 = icmp ult <16 x i8> %t230, %t234, !dbg !37
  %t236 = or <16 x i1> %t229, %t235, !dbg !37
  store <16 x i1> %t236, ptr %slot237, !dbg !37
  store i1 false, ptr %slot238, !dbg !38
  %t239 = load i1, ptr %slot50, !dbg !39
  br i1 %t239, label %if.then.51, label %if.else.52, !dbg !39
if.then.51:
  %t240 = load <16 x i1>, ptr %slot237, !dbg !40
  %t241 = bitcast <16 x i1> %t240 to i16, !dbg !40
  %t242 = zext i16 %t241 to i64, !dbg !40
  store i64 %t242, ptr %slot68, !dbg !40
  store i1 true, ptr %slot238, !dbg !41
  br label %if.end.50, !dbg !41
if.else.52:
  %t243 = load <16 x i8>, ptr %slot168, !dbg !42
  %t244 = call i32 @nupp.wrap.u32(double 0x4060000000000000), !dbg !42
  %t245 = trunc i32 %t244 to i8, !dbg !42
  %t246 = insertelement <16 x i8> poison, i8 %t245, i64 0, !dbg !42
  %t247 = shufflevector <16 x i8> %t246, <16 x i8> poison, <16 x i32> zeroinitializer, !dbg !42
  %t248 = icmp uge <16 x i8> %t243, %t247, !dbg !42
  store <16 x i1> %t248, ptr %slot249, !dbg !42
  %t250 = load <16 x i1>, ptr %slot237, !dbg !43
  %t251 = load <16 x i1>, ptr %slot249, !dbg !43
  %t252 = or <16 x i1> %t250, %t251, !dbg !43
  %t253 = bitcast <16 x i1> %t252 to i16, !dbg !43
  %t254 = zext i16 %t253 to i64, !dbg !43
  store i64 %t254, ptr %slot68, !dbg !43
  %t255 = load i64, ptr %slot68, !dbg !44
  %t256 = call i64 @llvm.fptosi.sat.i64.f64(double 0x0000000000000000), !dbg !44
  %t257 = call i64 @llvm.fptoui.sat.i64.f64(double 0x0000000000000000), !dbg !44
  %t258 = fcmp olt double 0x0000000000000000, 0.0, !dbg !44
  %t259 = select i1 %t258, i64 %t256, i64 %t257, !dbg !44
  %t260 = icmp ne i64 %t255, %t259, !dbg !44
  br i1 %t260, label %if.then.54, label %if.else.55, !dbg !44
if.then.54:
  %t261 = load <16 x i1>, ptr %slot249, !dbg !45
  %t262 = sext <16 x i1> %t261 to <16 x i8>, !dbg !45
  %t263 = call <16 x i8> asm "", "=w,0"(<16 x i8> %t262), !dbg !45
  %t264 = bitcast <16 x i8> %t263 to <4 x i32>, !dbg !45
  %t265 = shufflevector <4 x i32> %t264, <4 x i32> poison, <4 x i32> <i32 0, i32 1, i32 2, i32 3>, !dbg !45
  %t266 = call <4 x i32> @llvm.aarch64.neon.umaxp.v4i32(<4 x i32> %t265, <4 x i32> %t265), !dbg !45
  %t267 = bitcast <4 x i32> %t266 to <2 x i64>, !dbg !45
  %t268 = extractelement <2 x i64> %t267, i32 0, !dbg !45
  %t269 = icmp ne i64 %t268, 0, !dbg !45
  store i1 %t269, ptr %slot238, !dbg !45
  %t270 = load i1, ptr %slot238, !dbg !46
  br i1 %t270, label %if.then.57, label %if.else.58, !dbg !46
if.then.57:
  %t271 = load <16 x i1>, ptr %slot237, !dbg !47
  %t272 = bitcast <16 x i1> %t271 to i16, !dbg !47
  %t273 = zext i16 %t272 to i64, !dbg !47
  store i64 %t273, ptr %slot68, !dbg !47
  br label %if.end.56, !dbg !47
if.else.58:
  br label %if.end.56, !dbg !47
if.end.56:
  br label %if.end.53, !dbg !47
if.else.55:
  br label %if.end.53, !dbg !47
if.end.53:
  br label %if.end.50, !dbg !47
if.end.50:
  %t274 = load i1, ptr %slot238, !dbg !48
  br i1 %t274, label %if.then.60, label %if.else.61, !dbg !48
if.then.60:
  %t275 = load i32, ptr %slot33, !dbg !49
  %t276 = sub i32 %t275, 16, !dbg !49
  %t277 = add i32 %t276, 1, !dbg !49
  %t278 = zext i32 %t277 to i64, !dbg !49
  %t279 = icmp ne i64 %t278, 0, !dbg !49
  %t280 = sub i64 %t278, 1, !dbg !49
  %t281 = select i1 %t279, i64 %t280, i64 -1, !dbg !49
  %t282 = icmp ult i64 %t281, %t15, !dbg !49
  %t283 = sub i64 %t15, %t281, !dbg !49
  %t284 = icmp ult i64 %t283, 16, !dbg !49
  %t285 = select i1 %t284, i64 %t283, i64 16, !dbg !49
  %t286 = select i1 %t282, i64 %t285, i64 0, !dbg !49
  %t287 = trunc i64 %t286 to i32, !dbg !49
  %t288 = select i1 %t282, i64 %t281, i64 0, !dbg !49
  %t289 = getelementptr inbounds i8, ptr %t14, i64 %t288, !dbg !49
  %t290 = icmp eq i32 %t287, 16, !dbg !49
  br i1 %t290, label %simd.yes.62, label %simd.no.63, !dbg !49
simd.yes.62:
  %t291 = load <16 x i8>, ptr %t289, align 1, !dbg !49
  br label %simd.join.64, !dbg !49
simd.no.63:
  switch i32 %t287, label %tail.done.81 [ i32 1, label %tail.lane.65 i32 2, label %tail.lane.66 i32 3, label %tail.lane.67 i32 4, label %tail.lane.68 i32 5, label %tail.lane.69 i32 6, label %tail.lane.70 i32 7, label %tail.lane.71 i32 8, label %tail.lane.72 i32 9, label %tail.lane.73 i32 10, label %tail.lane.74 i32 11, label %tail.lane.75 i32 12, label %tail.lane.76 i32 13, label %tail.lane.77 i32 14, label %tail.lane.78 i32 15, label %tail.lane.79 i32 16, label %tail.lane.80 ], !dbg !49
tail.lane.80:
  %t292 = getelementptr inbounds i8, ptr %t289, i64 15, !dbg !49
  %t293 = load i8, ptr %t292, align 1, !dbg !49
  %t294 = insertelement <16 x i8> zeroinitializer, i8 %t293, i32 15, !dbg !49
  br label %tail.lane.79, !dbg !49
tail.lane.79:
  %t295 = phi <16 x i8> [ zeroinitializer, %simd.no.63 ], [ %t294, %tail.lane.80 ], !dbg !49
  %t296 = getelementptr inbounds i8, ptr %t289, i64 14, !dbg !49
  %t297 = load i8, ptr %t296, align 1, !dbg !49
  %t298 = insertelement <16 x i8> %t295, i8 %t297, i32 14, !dbg !49
  br label %tail.lane.78, !dbg !49
tail.lane.78:
  %t299 = phi <16 x i8> [ zeroinitializer, %simd.no.63 ], [ %t298, %tail.lane.79 ], !dbg !49
  %t300 = getelementptr inbounds i8, ptr %t289, i64 13, !dbg !49
  %t301 = load i8, ptr %t300, align 1, !dbg !49
  %t302 = insertelement <16 x i8> %t299, i8 %t301, i32 13, !dbg !49
  br label %tail.lane.77, !dbg !49
tail.lane.77:
  %t303 = phi <16 x i8> [ zeroinitializer, %simd.no.63 ], [ %t302, %tail.lane.78 ], !dbg !49
  %t304 = getelementptr inbounds i8, ptr %t289, i64 12, !dbg !49
  %t305 = load i8, ptr %t304, align 1, !dbg !49
  %t306 = insertelement <16 x i8> %t303, i8 %t305, i32 12, !dbg !49
  br label %tail.lane.76, !dbg !49
tail.lane.76:
  %t307 = phi <16 x i8> [ zeroinitializer, %simd.no.63 ], [ %t306, %tail.lane.77 ], !dbg !49
  %t308 = getelementptr inbounds i8, ptr %t289, i64 11, !dbg !49
  %t309 = load i8, ptr %t308, align 1, !dbg !49
  %t310 = insertelement <16 x i8> %t307, i8 %t309, i32 11, !dbg !49
  br label %tail.lane.75, !dbg !49
tail.lane.75:
  %t311 = phi <16 x i8> [ zeroinitializer, %simd.no.63 ], [ %t310, %tail.lane.76 ], !dbg !49
  %t312 = getelementptr inbounds i8, ptr %t289, i64 10, !dbg !49
  %t313 = load i8, ptr %t312, align 1, !dbg !49
  %t314 = insertelement <16 x i8> %t311, i8 %t313, i32 10, !dbg !49
  br label %tail.lane.74, !dbg !49
tail.lane.74:
  %t315 = phi <16 x i8> [ zeroinitializer, %simd.no.63 ], [ %t314, %tail.lane.75 ], !dbg !49
  %t316 = getelementptr inbounds i8, ptr %t289, i64 9, !dbg !49
  %t317 = load i8, ptr %t316, align 1, !dbg !49
  %t318 = insertelement <16 x i8> %t315, i8 %t317, i32 9, !dbg !49
  br label %tail.lane.73, !dbg !49
tail.lane.73:
  %t319 = phi <16 x i8> [ zeroinitializer, %simd.no.63 ], [ %t318, %tail.lane.74 ], !dbg !49
  %t320 = getelementptr inbounds i8, ptr %t289, i64 8, !dbg !49
  %t321 = load i8, ptr %t320, align 1, !dbg !49
  %t322 = insertelement <16 x i8> %t319, i8 %t321, i32 8, !dbg !49
  br label %tail.lane.72, !dbg !49
tail.lane.72:
  %t323 = phi <16 x i8> [ zeroinitializer, %simd.no.63 ], [ %t322, %tail.lane.73 ], !dbg !49
  %t324 = getelementptr inbounds i8, ptr %t289, i64 7, !dbg !49
  %t325 = load i8, ptr %t324, align 1, !dbg !49
  %t326 = insertelement <16 x i8> %t323, i8 %t325, i32 7, !dbg !49
  br label %tail.lane.71, !dbg !49
tail.lane.71:
  %t327 = phi <16 x i8> [ zeroinitializer, %simd.no.63 ], [ %t326, %tail.lane.72 ], !dbg !49
  %t328 = getelementptr inbounds i8, ptr %t289, i64 6, !dbg !49
  %t329 = load i8, ptr %t328, align 1, !dbg !49
  %t330 = insertelement <16 x i8> %t327, i8 %t329, i32 6, !dbg !49
  br label %tail.lane.70, !dbg !49
tail.lane.70:
  %t331 = phi <16 x i8> [ zeroinitializer, %simd.no.63 ], [ %t330, %tail.lane.71 ], !dbg !49
  %t332 = getelementptr inbounds i8, ptr %t289, i64 5, !dbg !49
  %t333 = load i8, ptr %t332, align 1, !dbg !49
  %t334 = insertelement <16 x i8> %t331, i8 %t333, i32 5, !dbg !49
  br label %tail.lane.69, !dbg !49
tail.lane.69:
  %t335 = phi <16 x i8> [ zeroinitializer, %simd.no.63 ], [ %t334, %tail.lane.70 ], !dbg !49
  %t336 = getelementptr inbounds i8, ptr %t289, i64 4, !dbg !49
  %t337 = load i8, ptr %t336, align 1, !dbg !49
  %t338 = insertelement <16 x i8> %t335, i8 %t337, i32 4, !dbg !49
  br label %tail.lane.68, !dbg !49
tail.lane.68:
  %t339 = phi <16 x i8> [ zeroinitializer, %simd.no.63 ], [ %t338, %tail.lane.69 ], !dbg !49
  %t340 = getelementptr inbounds i8, ptr %t289, i64 3, !dbg !49
  %t341 = load i8, ptr %t340, align 1, !dbg !49
  %t342 = insertelement <16 x i8> %t339, i8 %t341, i32 3, !dbg !49
  br label %tail.lane.67, !dbg !49
tail.lane.67:
  %t343 = phi <16 x i8> [ zeroinitializer, %simd.no.63 ], [ %t342, %tail.lane.68 ], !dbg !49
  %t344 = getelementptr inbounds i8, ptr %t289, i64 2, !dbg !49
  %t345 = load i8, ptr %t344, align 1, !dbg !49
  %t346 = insertelement <16 x i8> %t343, i8 %t345, i32 2, !dbg !49
  br label %tail.lane.66, !dbg !49
tail.lane.66:
  %t347 = phi <16 x i8> [ zeroinitializer, %simd.no.63 ], [ %t346, %tail.lane.67 ], !dbg !49
  %t348 = getelementptr inbounds i8, ptr %t289, i64 1, !dbg !49
  %t349 = load i8, ptr %t348, align 1, !dbg !49
  %t350 = insertelement <16 x i8> %t347, i8 %t349, i32 1, !dbg !49
  br label %tail.lane.65, !dbg !49
tail.lane.65:
  %t351 = phi <16 x i8> [ zeroinitializer, %simd.no.63 ], [ %t350, %tail.lane.66 ], !dbg !49
  %t352 = getelementptr inbounds i8, ptr %t289, i64 0, !dbg !49
  %t353 = load i8, ptr %t352, align 1, !dbg !49
  %t354 = insertelement <16 x i8> %t351, i8 %t353, i32 0, !dbg !49
  br label %tail.done.81, !dbg !49
tail.done.81:
  %t355 = phi <16 x i8> [ zeroinitializer, %simd.no.63 ], [ %t354, %tail.lane.65 ], !dbg !49
  br label %simd.join.64, !dbg !49
simd.join.64:
  %t356 = phi <16 x i8> [ %t291, %simd.yes.62 ], [ %t355, %tail.done.81 ], !dbg !49
  store <16 x i8> %t356, ptr %slot357, !dbg !49
  %t358 = load <16 x i8>, ptr %slot357, !dbg !50
  %t359 = load <16 x i8>, ptr %slot168, !dbg !50
  %t360 = shufflevector <16 x i8> %t358, <16 x i8> %t359, <16 x i32> <i32 15, i32 16, i32 17, i32 18, i32 19, i32 20, i32 21, i32 22, i32 23, i32 24, i32 25, i32 26, i32 27, i32 28, i32 29, i32 30>, !dbg !50
  store <16 x i8> %t360, ptr %slot361, !dbg !50
  %t362 = load <16 x i8>, ptr %slot357, !dbg !51
  %t363 = load <16 x i8>, ptr %slot168, !dbg !51
  %t364 = shufflevector <16 x i8> %t362, <16 x i8> %t363, <16 x i32> <i32 14, i32 15, i32 16, i32 17, i32 18, i32 19, i32 20, i32 21, i32 22, i32 23, i32 24, i32 25, i32 26, i32 27, i32 28, i32 29>, !dbg !51
  store <16 x i8> %t364, ptr %slot365, !dbg !51
  %t366 = load <16 x i8>, ptr %slot357, !dbg !52
  %t367 = load <16 x i8>, ptr %slot168, !dbg !52
  %t368 = shufflevector <16 x i8> %t366, <16 x i8> %t367, <16 x i32> <i32 13, i32 14, i32 15, i32 16, i32 17, i32 18, i32 19, i32 20, i32 21, i32 22, i32 23, i32 24, i32 25, i32 26, i32 27, i32 28>, !dbg !52
  store <16 x i8> %t368, ptr %slot369, !dbg !52
  %t370 = call i32 @nupp.wrap.u32(double 0x0000000000000000), !dbg !53
  %t371 = trunc i32 %t370 to i8, !dbg !53
  %t372 = insertelement <16 x i8> poison, i8 %t371, i64 0, !dbg !53
  %t373 = shufflevector <16 x i8> %t372, <16 x i8> poison, <16 x i32> zeroinitializer, !dbg !53
  store <16 x i8> %t373, ptr %slot374, !dbg !53
  %t375 = load <16 x i8>, ptr %slot374, !dbg !54
  %t376 = call <16 x i8> @ks___nupp_const_decode_fused_24f677cbe166e03f__5f5f6e757070436f6e73745f6465636f646546757365645f32346636373763626531363665303366_helper_nibble_table(<16 x i8> %t375, i32 2, i32 2, i32 2, i32 2, i32 2, i32 2, i32 2, i32 2, i32 128, i32 128, i32 128, i32 128, i32 33, i32 1, i32 21, i32 73), !dbg !54
  store <16 x i8> %t376, ptr %slot377, !dbg !54
  %t378 = load <16 x i8>, ptr %slot374, !dbg !55
  %t379 = call <16 x i8> @ks___nupp_const_decode_fused_24f677cbe166e03f__5f5f6e757070436f6e73745f6465636f646546757365645f32346636373763626531363665303366_helper_nibble_table(<16 x i8> %t378, i32 231, i32 163, i32 131, i32 131, i32 139, i32 203, i32 203, i32 203, i32 203, i32 203, i32 203, i32 203, i32 203, i32 219, i32 203, i32 203), !dbg !55
  store <16 x i8> %t379, ptr %slot380, !dbg !55
  %t381 = load <16 x i8>, ptr %slot374, !dbg !56
  %t382 = call <16 x i8> @ks___nupp_const_decode_fused_24f677cbe166e03f__5f5f6e757070436f6e73745f6465636f646546757365645f32346636373763626531363665303366_helper_nibble_table(<16 x i8> %t381, i32 1, i32 1, i32 1, i32 1, i32 1, i32 1, i32 1, i32 1, i32 230, i32 174, i32 186, i32 186, i32 1, i32 1, i32 1, i32 1), !dbg !56
  store <16 x i8> %t382, ptr %slot383, !dbg !56
  %t384 = load <16 x i8>, ptr %slot377, !dbg !57
  %t385 = load <16 x i8>, ptr %slot361, !dbg !57
  %t386 = call i32 @nupp.wrap.u32(double 0x4010000000000000), !dbg !57
  %t387 = trunc i32 %t386 to i8, !dbg !57
  %t388 = insertelement <16 x i8> poison, i8 %t387, i64 0, !dbg !57
  %t389 = shufflevector <16 x i8> %t388, <16 x i8> poison, <16 x i32> zeroinitializer, !dbg !57
  %t390 = and <16 x i8> %t389, splat (i8 7), !dbg !57
  %t391 = lshr <16 x i8> %t385, %t390, !dbg !57
  %t392 = call i32 @nupp.wrap.u32(double 0x3FF0000000000000), !dbg !57
  %t393 = trunc i32 %t392 to i8, !dbg !57
  %t394 = insertelement <16 x i8> poison, i8 %t393, i64 0, !dbg !57
  %t395 = shufflevector <16 x i8> %t394, <16 x i8> poison, <16 x i32> zeroinitializer, !dbg !57
  %t396 = add <16 x i8> %t391, %t395, !dbg !57
  %t397 = sub <16 x i8> %t396, splat (i8 1), !dbg !57
  %t398 = call <16 x i8> @llvm.aarch64.neon.tbl1.v16i8(<16 x i8> %t384, <16 x i8> %t397), !dbg !57
  %t399 = load <16 x i8>, ptr %slot380, !dbg !57
  %t400 = load <16 x i8>, ptr %slot361, !dbg !57
  %t401 = call i32 @nupp.wrap.u32(double 0x402E000000000000), !dbg !57
  %t402 = trunc i32 %t401 to i8, !dbg !57
  %t403 = insertelement <16 x i8> poison, i8 %t402, i64 0, !dbg !57
  %t404 = shufflevector <16 x i8> %t403, <16 x i8> poison, <16 x i32> zeroinitializer, !dbg !57
  %t405 = and <16 x i8> %t400, %t404, !dbg !57
  %t406 = call i32 @nupp.wrap.u32(double 0x3FF0000000000000), !dbg !57
  %t407 = trunc i32 %t406 to i8, !dbg !57
  %t408 = insertelement <16 x i8> poison, i8 %t407, i64 0, !dbg !57
  %t409 = shufflevector <16 x i8> %t408, <16 x i8> poison, <16 x i32> zeroinitializer, !dbg !57
  %t410 = add <16 x i8> %t405, %t409, !dbg !57
  %t411 = sub <16 x i8> %t410, splat (i8 1), !dbg !57
  %t412 = call <16 x i8> @llvm.aarch64.neon.tbl1.v16i8(<16 x i8> %t399, <16 x i8> %t411), !dbg !57
  %t413 = and <16 x i8> %t398, %t412, !dbg !57
  %t414 = load <16 x i8>, ptr %slot383, !dbg !57
  %t415 = load <16 x i8>, ptr %slot168, !dbg !57
  %t416 = call i32 @nupp.wrap.u32(double 0x4010000000000000), !dbg !57
  %t417 = trunc i32 %t416 to i8, !dbg !57
  %t418 = insertelement <16 x i8> poison, i8 %t417, i64 0, !dbg !57
  %t419 = shufflevector <16 x i8> %t418, <16 x i8> poison, <16 x i32> zeroinitializer, !dbg !57
  %t420 = and <16 x i8> %t419, splat (i8 7), !dbg !57
  %t421 = lshr <16 x i8> %t415, %t420, !dbg !57
  %t422 = call i32 @nupp.wrap.u32(double 0x3FF0000000000000), !dbg !57
  %t423 = trunc i32 %t422 to i8, !dbg !57
  %t424 = insertelement <16 x i8> poison, i8 %t423, i64 0, !dbg !57
  %t425 = shufflevector <16 x i8> %t424, <16 x i8> poison, <16 x i32> zeroinitializer, !dbg !57
  %t426 = add <16 x i8> %t421, %t425, !dbg !57
  %t427 = sub <16 x i8> %t426, splat (i8 1), !dbg !57
  %t428 = call <16 x i8> @llvm.aarch64.neon.tbl1.v16i8(<16 x i8> %t414, <16 x i8> %t427), !dbg !57
  %t429 = and <16 x i8> %t413, %t428, !dbg !57
  store <16 x i8> %t429, ptr %slot430, !dbg !57
  %t431 = call i32 @nupp.wrap.u32(double 0x4060000000000000), !dbg !58
  %t432 = trunc i32 %t431 to i8, !dbg !58
  %t433 = insertelement <16 x i8> poison, i8 %t432, i64 0, !dbg !58
  %t434 = shufflevector <16 x i8> %t433, <16 x i8> poison, <16 x i32> zeroinitializer, !dbg !58
  %t435 = call i32 @nupp.wrap.u32(double 0x0000000000000000), !dbg !58
  %t436 = trunc i32 %t435 to i8, !dbg !58
  %t437 = insertelement <16 x i8> poison, i8 %t436, i64 0, !dbg !58
  %t438 = shufflevector <16 x i8> %t437, <16 x i8> poison, <16 x i32> zeroinitializer, !dbg !58
  %t439 = load <16 x i8>, ptr %slot365, !dbg !58
  %t440 = call i32 @nupp.wrap.u32(double 0x406C000000000000), !dbg !58
  %t441 = trunc i32 %t440 to i8, !dbg !58
  %t442 = insertelement <16 x i8> poison, i8 %t441, i64 0, !dbg !58
  %t443 = shufflevector <16 x i8> %t442, <16 x i8> poison, <16 x i32> zeroinitializer, !dbg !58
  %t444 = icmp uge <16 x i8> %t439, %t443, !dbg !58
  %t445 = load <16 x i8>, ptr %slot369, !dbg !58
  %t446 = call i32 @nupp.wrap.u32(double 0x406E000000000000), !dbg !58
  %t447 = trunc i32 %t446 to i8, !dbg !58
  %t448 = insertelement <16 x i8> poison, i8 %t447, i64 0, !dbg !58
  %t449 = shufflevector <16 x i8> %t448, <16 x i8> poison, <16 x i32> zeroinitializer, !dbg !58
  %t450 = icmp uge <16 x i8> %t445, %t449, !dbg !58
  %t451 = or <16 x i1> %t444, %t450, !dbg !58
  %t452 = select <16 x i1> %t451, <16 x i8> %t434, <16 x i8> %t438, !dbg !58
  store <16 x i8> %t452, ptr %slot453, !dbg !58
  %t454 = load <16 x i8>, ptr %slot430, !dbg !59
  %t455 = load <16 x i8>, ptr %slot453, !dbg !59
  %t456 = xor <16 x i8> %t454, %t455, !dbg !59
  %t457 = call i32 @nupp.wrap.u32(double 0x0000000000000000), !dbg !59
  %t458 = trunc i32 %t457 to i8, !dbg !59
  %t459 = zext i8 %t458 to i32, !dbg !59
  %t460 = call i32 @llvm.aarch64.neon.umaxv.i32.v16i8(<16 x i8> %t456), !dbg !59
  %t461 = trunc i32 %t460 to i8, !dbg !59
  %t462 = zext i8 %t461 to i32, !dbg !59
  %t463 = icmp ne i32 %t462, 0, !dbg !59
  br i1 %t463, label %if.then.83, label %if.else.84, !dbg !59
if.then.83:
  store i1 true, ptr %slot56, !dbg !60
  br label %if.end.82, !dbg !60
if.else.84:
  %t464 = load <16 x i8>, ptr %slot168, !dbg !61
  %t465 = load <16 x i8>, ptr %slot168, !dbg !61
  %t466 = shufflevector <16 x i8> %t464, <16 x i8> %t465, <16 x i32> <i32 15, i32 16, i32 17, i32 18, i32 19, i32 20, i32 21, i32 22, i32 23, i32 24, i32 25, i32 26, i32 27, i32 28, i32 29, i32 30>, !dbg !61
  %t467 = extractelement <16 x i8> %t466, i32 0, !dbg !61
  %t468 = zext i8 %t467 to i32, !dbg !61
  %t469 = icmp uge i32 %t468, 128, !dbg !61
  store i1 %t469, ptr %slot50, !dbg !61
  br label %if.end.82, !dbg !61
if.end.82:
  br label %if.end.59, !dbg !61
if.else.61:
  store i1 false, ptr %slot50, !dbg !62
  br label %if.end.59, !dbg !62
if.end.59:
  %t470 = load i1, ptr %slot56, !dbg !63
  %t471 = xor i1 %t470, true, !dbg !63
  br i1 %t471, label %if.then.86, label %if.else.87, !dbg !63
if.then.86:
  store i32 16, ptr %slot70, !dbg !64
  br label %if.end.85, !dbg !64
if.else.87:
  %t472 = call i64 @llvm.fptosi.sat.i64.f64(double 0x0000000000000000), !dbg !65
  %t473 = call i64 @llvm.fptoui.sat.i64.f64(double 0x0000000000000000), !dbg !65
  %t474 = fcmp olt double 0x0000000000000000, 0.0, !dbg !65
  %t475 = select i1 %t474, i64 %t472, i64 %t473, !dbg !65
  store i64 %t475, ptr %slot68, !dbg !65
  br label %if.end.85, !dbg !65
if.end.85:
  br label %if.end.22, !dbg !65
if.else.26:
  br label %if.end.22, !dbg !65
if.end.22:
  br label %if.end.19, !dbg !65
if.else.21:
  br label %if.end.19, !dbg !65
if.end.19:
  %t476 = load i32, ptr %slot70, !dbg !66
  %t477 = icmp eq i32 %t476, 0, !dbg !66
  br i1 %t477, label %and.rhs.89, label %and.end.90, !dbg !66
and.rhs.89:
  %t478 = load i1, ptr %slot49, !dbg !66
  %t479 = xor i1 %t478, true, !dbg !66
  br label %and.end.90, !dbg !66
and.end.90:
  %t480 = phi i1 [ false, %if.end.19 ], [ %t479, %and.rhs.89 ], !dbg !66
  br i1 %t480, label %if.then.91, label %if.else.92, !dbg !66
if.then.91:
  store i1 true, ptr %slot49, !dbg !67
  %t481 = call i32 @nupp.wrap.u32(double 0x3FF0000000000000), !dbg !68
  store i32 %t481, ptr %slot482, !dbg !68
  store i1 true, ptr %slot483, !dbg !69
  br label %while.head.93, !dbg !70
while.head.93:
  %t484 = load i1, ptr %slot483, !dbg !70
  br i1 %t484, label %and.rhs.96, label %and.end.97, !dbg !70
and.rhs.96:
  %t485 = load i32, ptr %slot482, !dbg !70
  %t486 = icmp ule i32 %t485, 3, !dbg !70
  br label %and.end.97, !dbg !70
and.end.97:
  %t487 = phi i1 [ false, %while.head.93 ], [ %t486, %and.rhs.96 ], !dbg !70
  br i1 %t487, label %and.rhs.98, label %and.end.99, !dbg !70
and.rhs.98:
  %t488 = load i32, ptr %slot482, !dbg !70
  %t489 = load i32, ptr %slot33, !dbg !70
  %t490 = icmp ule i32 %t488, %t489, !dbg !70
  br label %and.end.99, !dbg !70
and.end.99:
  %t491 = phi i1 [ false, %and.end.97 ], [ %t490, %and.rhs.98 ], !dbg !70
  br i1 %t491, label %while.body.94, label %while.end.95, !dbg !70
while.body.94:
  %t492 = load i32, ptr %slot33, !dbg !71
  %t493 = load i32, ptr %slot482, !dbg !71
  %t494 = sub i32 %t492, %t493, !dbg !71
  %t495 = zext i32 %t494 to i64, !dbg !71
  %t496 = icmp uge i64 %t495, %t15, !dbg !71
  br i1 %t496, label %lua.raise.100, label %lua.ok.101, !prof !7, !dbg !71
lua.raise.100:
  %t497 = getelementptr inbounds ptr, ptr %t1, i64 11, !dbg !71
  %rt.raise.498 = load ptr, ptr %t497, !invariant.load !8, !dbg !71
  call void %rt.raise.498(ptr %L, i64 3) nomerge, !dbg !71
  unreachable, !dbg !71
lua.ok.101:
  %t499 = getelementptr inbounds i8, ptr %t14, i64 %t495, !dbg !71
  %t500 = load i8, ptr %t499, !dbg !71
  %t501 = zext i8 %t500 to i32, !dbg !71
  store i32 %t501, ptr %slot502, !dbg !71
  %t503 = load i32, ptr %slot502, !dbg !72
  %t504 = icmp ult i32 %t503, 128, !dbg !72
  br i1 %t504, label %if.then.103, label %if.else.104, !dbg !72
if.then.103:
  store i1 false, ptr %slot483, !dbg !73
  br label %if.end.102, !dbg !73
if.else.104:
  %t505 = load i32, ptr %slot502, !dbg !73
  %t506 = icmp uge i32 %t505, 192, !dbg !73
  br i1 %t506, label %if.then.105, label %if.else.106, !dbg !73
if.then.105:
  %t507 = load i32, ptr %slot502, !dbg !74
  %t508 = icmp ult i32 %t507, 194, !dbg !74
  br i1 %t508, label %or.end.109, label %or.rhs.108, !dbg !74
or.rhs.108:
  %t509 = load i32, ptr %slot502, !dbg !74
  %t510 = icmp ugt i32 %t509, 244, !dbg !74
  br label %or.end.109, !dbg !74
or.end.109:
  %t511 = phi i1 [ true, %if.then.105 ], [ %t510, %or.rhs.108 ], !dbg !74
  br i1 %t511, label %if.then.110, label %if.else.111, !dbg !74
if.then.110:
  call void @lua_pushvalue(ptr %L, i32 2), !dbg !75
  %t512 = call i32 @nupp.wrap.u32(double 0x4000000000000000), !dbg !75
  %t513 = uitofp i32 %t512 to double, !dbg !75
  call void @lua_pushnumber(ptr %L, double %t513), !dbg !75
  %t514 = load i32, ptr %slot33, !dbg !75
  %t515 = load i32, ptr %slot482, !dbg !75
  %t516 = sub i32 %t514, %t515, !dbg !75
  %t517 = add i32 %t516, 1, !dbg !75
  %t518 = uitofp i32 %t517 to double, !dbg !75
  call void @lua_pushnumber(ptr %L, double %t518), !dbg !75
  ret i32 3, !dbg !75
if.else.111:
  br label %if.end.107, !dbg !75
if.end.107:
  %t519 = call i32 @nupp.wrap.u32(double 0x4008000000000000), !dbg !76
  store i32 %t519, ptr %slot520, !dbg !76
  %t521 = load i32, ptr %slot502, !dbg !77
  %t522 = icmp ule i32 %t521, 223, !dbg !77
  br i1 %t522, label %if.then.113, label %if.else.114, !dbg !77
if.then.113:
  %t523 = call i32 @nupp.wrap.u32(double 0x3FF0000000000000), !dbg !78
  store i32 %t523, ptr %slot520, !dbg !78
  br label %if.end.112, !dbg !78
if.else.114:
  %t524 = load i32, ptr %slot502, !dbg !78
  %t525 = icmp ule i32 %t524, 239, !dbg !78
  br i1 %t525, label %if.then.115, label %if.else.116, !dbg !78
if.then.115:
  %t526 = call i32 @nupp.wrap.u32(double 0x4000000000000000), !dbg !79
  store i32 %t526, ptr %slot520, !dbg !79
  br label %if.end.112, !dbg !79
if.else.116:
  br label %if.end.112, !dbg !79
if.end.112:
  %t527 = load i32, ptr %slot520, !dbg !80
  %t528 = load i32, ptr %slot482, !dbg !80
  %t529 = icmp uge i32 %t527, %t528, !dbg !80
  br i1 %t529, label %if.then.118, label %if.else.119, !dbg !80
if.then.118:
  %t530 = load i32, ptr %slot520, !dbg !81
  %t531 = load i32, ptr %slot482, !dbg !81
  %t532 = sub i32 %t530, %t531, !dbg !81
  %t533 = add i32 %t532, 1, !dbg !81
  store i32 %t533, ptr %slot43, !dbg !81
  store i1 true, ptr %slot46, !dbg !82
  %t534 = load i32, ptr %slot33, !dbg !83
  %t535 = sub i32 %t534, 1, !dbg !83
  store i32 %t535, ptr %slot48, !dbg !83
  %t536 = load i32, ptr %slot482, !dbg !84
  %t537 = icmp eq i32 %t536, 1, !dbg !84
  br i1 %t537, label %if.then.121, label %if.else.122, !dbg !84
if.then.121:
  %t538 = load i32, ptr %slot502, !dbg !85
  %t539 = icmp eq i32 %t538, 224, !dbg !85
  br i1 %t539, label %if.then.124, label %if.else.125, !dbg !85
if.then.124:
  %t540 = call i32 @nupp.wrap.u32(double 0x3FF0000000000000), !dbg !86
  store i32 %t540, ptr %slot45, !dbg !86
  br label %if.end.123, !dbg !86
if.else.125:
  %t541 = load i32, ptr %slot502, !dbg !86
  %t542 = icmp eq i32 %t541, 237, !dbg !86
  br i1 %t542, label %if.then.126, label %if.else.127, !dbg !86
if.then.126:
  %t543 = call i32 @nupp.wrap.u32(double 0x4000000000000000), !dbg !87
  store i32 %t543, ptr %slot45, !dbg !87
  br label %if.end.123, !dbg !87
if.else.127:
  %t544 = load i32, ptr %slot502, !dbg !87
  %t545 = icmp eq i32 %t544, 240, !dbg !87
  br i1 %t545, label %if.then.128, label %if.else.129, !dbg !87
if.then.128:
  %t546 = call i32 @nupp.wrap.u32(double 0x4008000000000000), !dbg !88
  store i32 %t546, ptr %slot45, !dbg !88
  br label %if.end.123, !dbg !88
if.else.129:
  %t547 = load i32, ptr %slot502, !dbg !88
  %t548 = icmp eq i32 %t547, 244, !dbg !88
  br i1 %t548, label %if.then.130, label %if.else.131, !dbg !88
if.then.130:
  %t549 = call i32 @nupp.wrap.u32(double 0x4010000000000000), !dbg !89
  store i32 %t549, ptr %slot45, !dbg !89
  br label %if.end.123, !dbg !89
if.else.131:
  br label %if.end.123, !dbg !89
if.end.123:
  br label %if.end.120, !dbg !89
if.else.122:
  br label %if.end.120, !dbg !89
if.end.120:
  br label %if.end.117, !dbg !89
if.else.119:
  br label %if.end.117, !dbg !89
if.end.117:
  store i1 false, ptr %slot483, !dbg !90
  br label %if.end.102, !dbg !90
if.else.106:
  %t550 = load i32, ptr %slot482, !dbg !91
  %t551 = add i32 %t550, 1, !dbg !91
  store i32 %t551, ptr %slot482, !dbg !91
  br label %if.end.102, !dbg !91
if.end.102:
  br label %while.head.93, !dbg !91
while.end.95:
  br label %if.end.88, !dbg !91
if.else.92:
  %t552 = load i32, ptr %slot70, !dbg !91
  %t553 = icmp eq i32 %t552, 0, !dbg !91
  br i1 %t553, label %if.then.132, label %if.else.133, !dbg !91
if.then.132:
  %t554 = load i32, ptr %slot33, !dbg !92
  %t555 = load i32, ptr %slot20, !dbg !92
  %t556 = icmp ult i32 %t554, %t555, !dbg !92
  br i1 %t556, label %if.then.135, label %if.else.136, !dbg !92
if.then.135:
  %t557 = load i32, ptr %slot33, !dbg !93
  %t558 = zext i32 %t557 to i64, !dbg !93
  %t559 = getelementptr inbounds i8, ptr %t14, i64 %t558, !dbg !93
  %t560 = load i8, ptr %t559, !dbg !93
  %t561 = zext i8 %t560 to i32, !dbg !93
  store i32 %t561, ptr %slot562, !dbg !93
  %t563 = load i32, ptr %slot562, !dbg !94
  %t564 = icmp eq i32 %t563, 34, !dbg !94
  br i1 %t564, label %or.end.139, label %or.rhs.138, !dbg !94
or.rhs.138:
  %t565 = load i32, ptr %slot562, !dbg !94
  %t566 = icmp eq i32 %t565, 92, !dbg !94
  br label %or.end.139, !dbg !94
or.end.139:
  %t567 = phi i1 [ true, %if.then.135 ], [ %t566, %or.rhs.138 ], !dbg !94
  br i1 %t567, label %or.end.141, label %or.rhs.140, !dbg !94
or.rhs.140:
  %t568 = load i32, ptr %slot562, !dbg !94
  %t569 = icmp ult i32 %t568, 32, !dbg !94
  br label %or.end.141, !dbg !94
or.end.141:
  %t570 = phi i1 [ true, %or.end.139 ], [ %t569, %or.rhs.140 ], !dbg !94
  br i1 %t570, label %or.end.143, label %or.rhs.142, !dbg !94
or.rhs.142:
  %t571 = load i32, ptr %slot562, !dbg !94
  %t572 = icmp eq i32 %t571, 123, !dbg !94
  br label %or.end.143, !dbg !94
or.end.143:
  %t573 = phi i1 [ true, %or.end.141 ], [ %t572, %or.rhs.142 ], !dbg !94
  br i1 %t573, label %or.end.145, label %or.rhs.144, !dbg !94
or.rhs.144:
  %t574 = load i32, ptr %slot562, !dbg !94
  %t575 = icmp eq i32 %t574, 125, !dbg !94
  br label %or.end.145, !dbg !94
or.end.145:
  %t576 = phi i1 [ true, %or.end.143 ], [ %t575, %or.rhs.144 ], !dbg !94
  br i1 %t576, label %or.end.147, label %or.rhs.146, !dbg !94
or.rhs.146:
  %t577 = load i32, ptr %slot562, !dbg !94
  %t578 = icmp eq i32 %t577, 91, !dbg !94
  br label %or.end.147, !dbg !94
or.end.147:
  %t579 = phi i1 [ true, %or.end.145 ], [ %t578, %or.rhs.146 ], !dbg !94
  br i1 %t579, label %or.end.149, label %or.rhs.148, !dbg !94
or.rhs.148:
  %t580 = load i32, ptr %slot562, !dbg !94
  %t581 = icmp eq i32 %t580, 93, !dbg !94
  br label %or.end.149, !dbg !94
or.end.149:
  %t582 = phi i1 [ true, %or.end.147 ], [ %t581, %or.rhs.148 ], !dbg !94
  br i1 %t582, label %or.end.151, label %or.rhs.150, !dbg !94
or.rhs.150:
  %t583 = load i32, ptr %slot562, !dbg !94
  %t584 = icmp eq i32 %t583, 58, !dbg !94
  br label %or.end.151, !dbg !94
or.end.151:
  %t585 = phi i1 [ true, %or.end.149 ], [ %t584, %or.rhs.150 ], !dbg !94
  br i1 %t585, label %or.end.153, label %or.rhs.152, !dbg !94
or.rhs.152:
  %t586 = load i32, ptr %slot562, !dbg !94
  %t587 = icmp eq i32 %t586, 44, !dbg !94
  br label %or.end.153, !dbg !94
or.end.153:
  %t588 = phi i1 [ true, %or.end.151 ], [ %t587, %or.rhs.152 ], !dbg !94
  br i1 %t588, label %or.end.155, label %or.rhs.154, !dbg !94
or.rhs.154:
  %t589 = load i32, ptr %slot562, !dbg !94
  %t590 = icmp uge i32 %t589, 128, !dbg !94
  br label %or.end.155, !dbg !94
or.end.155:
  %t591 = phi i1 [ true, %or.end.153 ], [ %t590, %or.rhs.154 ], !dbg !94
  br i1 %t591, label %if.then.156, label %if.else.157, !dbg !94
if.then.156:
  %t592 = load i64, ptr %slot55, !dbg !95
  store i64 %t592, ptr %slot68, !dbg !95
  br label %if.end.137, !dbg !95
if.else.157:
  br label %if.end.137, !dbg !95
if.end.137:
  br label %if.end.134, !dbg !95
if.else.136:
  br label %if.end.134, !dbg !95
if.end.134:
  %t593 = call i32 @nupp.wrap.u32(double 0x3FF0000000000000), !dbg !96
  store i32 %t593, ptr %slot70, !dbg !96
  br label %if.end.88, !dbg !96
if.else.133:
  br label %if.end.88, !dbg !96
if.end.88:
  br label %while.head.158, !dbg !97
while.head.158:
  %t594 = load i64, ptr %slot68, !dbg !97
  %t595 = call i64 @llvm.fptosi.sat.i64.f64(double 0x0000000000000000), !dbg !97
  %t596 = call i64 @llvm.fptoui.sat.i64.f64(double 0x0000000000000000), !dbg !97
  %t597 = fcmp olt double 0x0000000000000000, 0.0, !dbg !97
  %t598 = select i1 %t597, i64 %t595, i64 %t596, !dbg !97
  %t599 = icmp ne i64 %t594, %t598, !dbg !97
  br i1 %t599, label %while.body.159, label %while.end.160, !dbg !97
while.body.159:
  %t600 = load i64, ptr %slot68, !dbg !98
  %t601 = call i64 @llvm.cttz.i64(i64 %t600, i1 false), !dbg !98
  %t602 = trunc i64 %t601 to i32, !dbg !98
  store i32 %t602, ptr %slot603, !dbg !98
  %t604 = load i64, ptr %slot68, !dbg !99
  %t605 = load i64, ptr %slot68, !dbg !99
  %t606 = call i64 @llvm.fptosi.sat.i64.f64(double 0x3FF0000000000000), !dbg !99
  %t607 = call i64 @llvm.fptoui.sat.i64.f64(double 0x3FF0000000000000), !dbg !99
  %t608 = fcmp olt double 0x3FF0000000000000, 0.0, !dbg !99
  %t609 = select i1 %t608, i64 %t606, i64 %t607, !dbg !99
  %t610 = sub i64 %t605, %t609, !dbg !99
  %t611 = and i64 %t604, %t610, !dbg !99
  store i64 %t611, ptr %slot68, !dbg !99
  %t612 = load i32, ptr %slot33, !dbg !100
  %t613 = load i32, ptr %slot603, !dbg !100
  %t614 = add i32 %t612, %t613, !dbg !100
  store i32 %t614, ptr %slot615, !dbg !100
  %t616 = load i32, ptr %slot615, !dbg !101
  %t617 = load i32, ptr %slot20, !dbg !101
  %t618 = icmp ult i32 %t616, %t617, !dbg !101
  br i1 %t618, label %if.then.162, label %if.else.163, !dbg !101
if.then.162:
  %t619 = load i32, ptr %slot615, !dbg !102
  %t620 = zext i32 %t619 to i64, !dbg !102
  %t621 = getelementptr inbounds i8, ptr %t14, i64 %t620, !dbg !102
  %t622 = load i8, ptr %t621, !dbg !102
  %t623 = zext i8 %t622 to i32, !dbg !102
  store i32 %t623, ptr %slot624, !dbg !102
  %t625 = load i32, ptr %slot43, !dbg !103
  %t626 = icmp ne i32 %t625, 0, !dbg !103
  br i1 %t626, label %and.rhs.165, label %and.end.166, !dbg !103
and.rhs.165:
  %t627 = load i1, ptr %slot46, !dbg !103
  %t628 = xor i1 %t627, true, !dbg !103
  br i1 %t628, label %or.end.168, label %or.rhs.167, !dbg !103
or.rhs.167:
  %t629 = load i32, ptr %slot615, !dbg !103
  %t630 = load i32, ptr %slot48, !dbg !103
  %t631 = add i32 %t630, 1, !dbg !103
  %t632 = icmp ne i32 %t629, %t631, !dbg !103
  br label %or.end.168, !dbg !103
or.end.168:
  %t633 = phi i1 [ true, %and.rhs.165 ], [ %t632, %or.rhs.167 ], !dbg !103
  br label %and.end.166, !dbg !103
and.end.166:
  %t634 = phi i1 [ false, %if.then.162 ], [ %t633, %or.end.168 ], !dbg !103
  br i1 %t634, label %if.then.169, label %if.else.170, !dbg !103
if.then.169:
  call void @lua_pushvalue(ptr %L, i32 2), !dbg !104
  %t635 = call i32 @nupp.wrap.u32(double 0x4000000000000000), !dbg !104
  %t636 = uitofp i32 %t635 to double, !dbg !104
  call void @lua_pushnumber(ptr %L, double %t636), !dbg !104
  %t637 = load i32, ptr %slot48, !dbg !104
  %t638 = add i32 %t637, 2, !dbg !104
  %t639 = uitofp i32 %t638 to double, !dbg !104
  call void @lua_pushnumber(ptr %L, double %t639), !dbg !104
  ret i32 3, !dbg !104
if.else.170:
  br label %if.end.164, !dbg !104
if.end.164:
  %t640 = load i32, ptr %slot624, !dbg !105
  %t641 = icmp uge i32 %t640, 128, !dbg !105
  br i1 %t641, label %if.then.172, label %if.else.173, !dbg !105
if.then.172:
  %t642 = load i32, ptr %slot624, !dbg !106
  %t643 = icmp ule i32 %t642, 191, !dbg !106
  store i1 %t643, ptr %slot644, !dbg !106
  %t645 = load i32, ptr %slot43, !dbg !107
  %t646 = icmp ne i32 %t645, 0, !dbg !107
  br i1 %t646, label %if.then.175, label %if.else.176, !dbg !107
if.then.175:
  %t647 = load i1, ptr %slot644, !dbg !108
  %t648 = xor i1 %t647, true, !dbg !108
  br i1 %t648, label %if.then.178, label %if.else.179, !dbg !108
if.then.178:
  call void @lua_pushvalue(ptr %L, i32 2), !dbg !109
  %t649 = call i32 @nupp.wrap.u32(double 0x4000000000000000), !dbg !109
  %t650 = uitofp i32 %t649 to double, !dbg !109
  call void @lua_pushnumber(ptr %L, double %t650), !dbg !109
  %t651 = load i32, ptr %slot615, !dbg !109
  %t652 = add i32 %t651, 1, !dbg !109
  %t653 = uitofp i32 %t652 to double, !dbg !109
  call void @lua_pushnumber(ptr %L, double %t653), !dbg !109
  ret i32 3, !dbg !109
if.else.179:
  br label %if.end.177, !dbg !109
if.end.177:
  %t654 = load i32, ptr %slot45, !dbg !110
  %t655 = icmp eq i32 %t654, 1, !dbg !110
  br i1 %t655, label %and.rhs.180, label %and.end.181, !dbg !110
and.rhs.180:
  %t656 = load i32, ptr %slot624, !dbg !110
  %t657 = icmp ult i32 %t656, 160, !dbg !110
  br label %and.end.181, !dbg !110
and.end.181:
  %t658 = phi i1 [ false, %if.end.177 ], [ %t657, %and.rhs.180 ], !dbg !110
  br i1 %t658, label %or.end.183, label %or.rhs.182, !dbg !110
or.rhs.182:
  %t659 = load i32, ptr %slot45, !dbg !110
  %t660 = icmp eq i32 %t659, 2, !dbg !110
  br i1 %t660, label %and.rhs.184, label %and.end.185, !dbg !110
and.rhs.184:
  %t661 = load i32, ptr %slot624, !dbg !110
  %t662 = icmp ugt i32 %t661, 159, !dbg !110
  br label %and.end.185, !dbg !110
and.end.185:
  %t663 = phi i1 [ false, %or.rhs.182 ], [ %t662, %and.rhs.184 ], !dbg !110
  br label %or.end.183, !dbg !110
or.end.183:
  %t664 = phi i1 [ true, %and.end.181 ], [ %t663, %and.end.185 ], !dbg !110
  br i1 %t664, label %or.end.187, label %or.rhs.186, !dbg !110
or.rhs.186:
  %t665 = load i32, ptr %slot45, !dbg !110
  %t666 = icmp eq i32 %t665, 3, !dbg !110
  br i1 %t666, label %and.rhs.188, label %and.end.189, !dbg !110
and.rhs.188:
  %t667 = load i32, ptr %slot624, !dbg !110
  %t668 = icmp ult i32 %t667, 144, !dbg !110
  br label %and.end.189, !dbg !110
and.end.189:
  %t669 = phi i1 [ false, %or.rhs.186 ], [ %t668, %and.rhs.188 ], !dbg !110
  br label %or.end.187, !dbg !110
or.end.187:
  %t670 = phi i1 [ true, %or.end.183 ], [ %t669, %and.end.189 ], !dbg !110
  br i1 %t670, label %or.end.191, label %or.rhs.190, !dbg !110
or.rhs.190:
  %t671 = load i32, ptr %slot45, !dbg !110
  %t672 = icmp eq i32 %t671, 4, !dbg !110
  br i1 %t672, label %and.rhs.192, label %and.end.193, !dbg !110
and.rhs.192:
  %t673 = load i32, ptr %slot624, !dbg !110
  %t674 = icmp ugt i32 %t673, 143, !dbg !110
  br label %and.end.193, !dbg !110
and.end.193:
  %t675 = phi i1 [ false, %or.rhs.190 ], [ %t674, %and.rhs.192 ], !dbg !110
  br label %or.end.191, !dbg !110
or.end.191:
  %t676 = phi i1 [ true, %or.end.187 ], [ %t675, %and.end.193 ], !dbg !110
  store i1 %t676, ptr %slot677, !dbg !110
  %t678 = load i1, ptr %slot677, !dbg !111
  br i1 %t678, label %if.then.195, label %if.else.196, !dbg !111
if.then.195:
  call void @lua_pushvalue(ptr %L, i32 2), !dbg !112
  %t679 = call i32 @nupp.wrap.u32(double 0x4000000000000000), !dbg !112
  %t680 = uitofp i32 %t679 to double, !dbg !112
  call void @lua_pushnumber(ptr %L, double %t680), !dbg !112
  %t681 = load i32, ptr %slot615, !dbg !112
  %t682 = add i32 %t681, 1, !dbg !112
  %t683 = uitofp i32 %t682 to double, !dbg !112
  call void @lua_pushnumber(ptr %L, double %t683), !dbg !112
  ret i32 3, !dbg !112
if.else.196:
  br label %if.end.194, !dbg !112
if.end.194:
  %t684 = load i32, ptr %slot43, !dbg !113
  %t685 = sub i32 %t684, 1, !dbg !113
  store i32 %t685, ptr %slot43, !dbg !113
  %t686 = call i32 @nupp.wrap.u32(double 0x0000000000000000), !dbg !114
  store i32 %t686, ptr %slot45, !dbg !114
  br label %if.end.174, !dbg !114
if.else.176:
  %t687 = load i1, ptr %slot644, !dbg !114
  br i1 %t687, label %or.end.198, label %or.rhs.197, !dbg !114
or.rhs.197:
  %t688 = load i32, ptr %slot624, !dbg !114
  %t689 = icmp ult i32 %t688, 194, !dbg !114
  br label %or.end.198, !dbg !114
or.end.198:
  %t690 = phi i1 [ true, %if.else.176 ], [ %t689, %or.rhs.197 ], !dbg !114
  br i1 %t690, label %or.end.200, label %or.rhs.199, !dbg !114
or.rhs.199:
  %t691 = load i32, ptr %slot624, !dbg !114
  %t692 = icmp ugt i32 %t691, 244, !dbg !114
  br label %or.end.200, !dbg !114
or.end.200:
  %t693 = phi i1 [ true, %or.end.198 ], [ %t692, %or.rhs.199 ], !dbg !114
  br i1 %t693, label %if.then.201, label %if.else.202, !dbg !114
if.then.201:
  call void @lua_pushvalue(ptr %L, i32 2), !dbg !115
  %t694 = call i32 @nupp.wrap.u32(double 0x4000000000000000), !dbg !115
  %t695 = uitofp i32 %t694 to double, !dbg !115
  call void @lua_pushnumber(ptr %L, double %t695), !dbg !115
  %t696 = load i32, ptr %slot615, !dbg !115
  %t697 = add i32 %t696, 1, !dbg !115
  %t698 = uitofp i32 %t697 to double, !dbg !115
  call void @lua_pushnumber(ptr %L, double %t698), !dbg !115
  ret i32 3, !dbg !115
if.else.202:
  %t699 = load i32, ptr %slot624, !dbg !115
  %t700 = icmp ule i32 %t699, 223, !dbg !115
  br i1 %t700, label %if.then.203, label %if.else.204, !dbg !115
if.then.203:
  %t701 = call i32 @nupp.wrap.u32(double 0x3FF0000000000000), !dbg !116
  store i32 %t701, ptr %slot43, !dbg !116
  br label %if.end.174, !dbg !116
if.else.204:
  %t702 = load i32, ptr %slot624, !dbg !116
  %t703 = icmp ule i32 %t702, 239, !dbg !116
  br i1 %t703, label %if.then.205, label %if.else.206, !dbg !116
if.then.205:
  %t704 = call i32 @nupp.wrap.u32(double 0x4000000000000000), !dbg !117
  store i32 %t704, ptr %slot43, !dbg !117
  %t705 = load i32, ptr %slot624, !dbg !118
  %t706 = icmp eq i32 %t705, 224, !dbg !118
  br i1 %t706, label %if.then.208, label %if.else.209, !dbg !118
if.then.208:
  %t707 = call i32 @nupp.wrap.u32(double 0x3FF0000000000000), !dbg !119
  store i32 %t707, ptr %slot45, !dbg !119
  br label %if.end.207, !dbg !119
if.else.209:
  %t708 = load i32, ptr %slot624, !dbg !119
  %t709 = icmp eq i32 %t708, 237, !dbg !119
  br i1 %t709, label %if.then.210, label %if.else.211, !dbg !119
if.then.210:
  %t710 = call i32 @nupp.wrap.u32(double 0x4000000000000000), !dbg !120
  store i32 %t710, ptr %slot45, !dbg !120
  br label %if.end.207, !dbg !120
if.else.211:
  br label %if.end.207, !dbg !120
if.end.207:
  br label %if.end.174, !dbg !120
if.else.206:
  %t711 = call i32 @nupp.wrap.u32(double 0x4008000000000000), !dbg !121
  store i32 %t711, ptr %slot43, !dbg !121
  %t712 = load i32, ptr %slot624, !dbg !122
  %t713 = icmp eq i32 %t712, 240, !dbg !122
  br i1 %t713, label %if.then.213, label %if.else.214, !dbg !122
if.then.213:
  %t714 = call i32 @nupp.wrap.u32(double 0x4008000000000000), !dbg !123
  store i32 %t714, ptr %slot45, !dbg !123
  br label %if.end.212, !dbg !123
if.else.214:
  %t715 = load i32, ptr %slot624, !dbg !123
  %t716 = icmp eq i32 %t715, 244, !dbg !123
  br i1 %t716, label %if.then.215, label %if.else.216, !dbg !123
if.then.215:
  %t717 = call i32 @nupp.wrap.u32(double 0x4010000000000000), !dbg !124
  store i32 %t717, ptr %slot45, !dbg !124
  br label %if.end.212, !dbg !124
if.else.216:
  br label %if.end.212, !dbg !124
if.end.212:
  br label %if.end.174, !dbg !124
if.end.174:
  store i1 true, ptr %slot46, !dbg !125
  %t718 = load i32, ptr %slot615, !dbg !126
  store i32 %t718, ptr %slot48, !dbg !126
  store i1 false, ptr %slot39, !dbg !127
  store i1 false, ptr %slot38, !dbg !128
  br label %if.end.171, !dbg !128
if.else.173:
  %t719 = load i32, ptr %slot43, !dbg !128
  %t720 = icmp ne i32 %t719, 0, !dbg !128
  br i1 %t720, label %if.then.217, label %if.else.218, !dbg !128
if.then.217:
  call void @lua_pushvalue(ptr %L, i32 2), !dbg !129
  %t721 = call i32 @nupp.wrap.u32(double 0x4000000000000000), !dbg !129
  %t722 = uitofp i32 %t721 to double, !dbg !129
  call void @lua_pushnumber(ptr %L, double %t722), !dbg !129
  %t723 = load i32, ptr %slot615, !dbg !129
  %t724 = add i32 %t723, 1, !dbg !129
  %t725 = uitofp i32 %t724 to double, !dbg !129
  call void @lua_pushnumber(ptr %L, double %t725), !dbg !129
  ret i32 3, !dbg !129
if.else.218:
  %t726 = load i32, ptr %slot624, !dbg !129
  %t727 = icmp eq i32 %t726, 92, !dbg !129
  br i1 %t727, label %if.then.219, label %if.else.220, !dbg !129
if.then.219:
  %t728 = load i1, ptr %slot36, !dbg !130
  %t729 = xor i1 %t728, true, !dbg !130
  br i1 %t729, label %if.then.222, label %if.else.223, !dbg !130
if.then.222:
  call void @lua_pushvalue(ptr %L, i32 2), !dbg !131
  %t730 = call i32 @nupp.wrap.u32(double 0x4010000000000000), !dbg !131
  %t731 = uitofp i32 %t730 to double, !dbg !131
  call void @lua_pushnumber(ptr %L, double %t731), !dbg !131
  %t732 = load i32, ptr %slot615, !dbg !131
  %t733 = add i32 %t732, 1, !dbg !131
  %t734 = uitofp i32 %t733 to double, !dbg !131
  call void @lua_pushnumber(ptr %L, double %t734), !dbg !131
  ret i32 3, !dbg !131
if.else.223:
  br label %if.end.221, !dbg !131
if.end.221:
  %t735 = load i1, ptr %slot39, !dbg !132
  br i1 %t735, label %and.rhs.225, label %and.end.226, !dbg !132
and.rhs.225:
  %t736 = load i32, ptr %slot615, !dbg !132
  %t737 = load i32, ptr %slot41, !dbg !132
  %t738 = add i32 %t737, 1, !dbg !132
  %t739 = icmp eq i32 %t736, %t738, !dbg !132
  br label %and.end.226, !dbg !132
and.end.226:
  %t740 = phi i1 [ false, %if.end.221 ], [ %t739, %and.rhs.225 ], !dbg !132
  br i1 %t740, label %if.then.227, label %if.else.228, !dbg !132
if.then.227:
  %t741 = load i1, ptr %slot38, !dbg !133
  %t742 = xor i1 %t741, true, !dbg !133
  store i1 %t742, ptr %slot38, !dbg !133
  br label %if.end.224, !dbg !133
if.else.228:
  store i1 true, ptr %slot38, !dbg !134
  br label %if.end.224, !dbg !134
if.end.224:
  store i1 true, ptr %slot39, !dbg !135
  %t743 = load i32, ptr %slot615, !dbg !136
  store i32 %t743, ptr %slot41, !dbg !136
  store i1 true, ptr %slot37, !dbg !137
  br label %if.end.171, !dbg !137
if.else.220:
  %t744 = load i1, ptr %slot39, !dbg !138
  br i1 %t744, label %and.rhs.229, label %and.end.230, !dbg !138
and.rhs.229:
  %t745 = load i32, ptr %slot615, !dbg !138
  %t746 = load i32, ptr %slot41, !dbg !138
  %t747 = add i32 %t746, 1, !dbg !138
  %t748 = icmp eq i32 %t745, %t747, !dbg !138
  br label %and.end.230, !dbg !138
and.end.230:
  %t749 = phi i1 [ false, %if.else.220 ], [ %t748, %and.rhs.229 ], !dbg !138
  br i1 %t749, label %and.rhs.231, label %and.end.232, !dbg !138
and.rhs.231:
  %t750 = load i1, ptr %slot38, !dbg !138
  br label %and.end.232, !dbg !138
and.end.232:
  %t751 = phi i1 [ false, %and.end.230 ], [ %t750, %and.rhs.231 ], !dbg !138
  store i1 %t751, ptr %slot752, !dbg !138
  %t753 = load i32, ptr %slot624, !dbg !139
  %t754 = icmp eq i32 %t753, 34, !dbg !139
  br i1 %t754, label %and.rhs.234, label %and.end.235, !dbg !139
and.rhs.234:
  %t755 = load i1, ptr %slot752, !dbg !139
  %t756 = xor i1 %t755, true, !dbg !139
  br label %and.end.235, !dbg !139
and.end.235:
  %t757 = phi i1 [ false, %and.end.232 ], [ %t756, %and.rhs.234 ], !dbg !139
  br i1 %t757, label %if.then.236, label %if.else.237, !dbg !139
if.then.236:
  %t758 = load i1, ptr %slot36, !dbg !140
  br i1 %t758, label %if.then.239, label %if.else.240, !dbg !140
if.then.239:
  %t759 = load i32, ptr %slot615, !dbg !141
  store i32 %t759, ptr %slot760, !dbg !141
  %t761 = load i1, ptr %slot37, !dbg !142
  br i1 %t761, label %if.then.242, label %if.else.243, !dbg !142
if.then.242:
  %t762 = load i32, ptr %slot615, !dbg !143
  %t763 = or i32 %t762, 2147483648, !dbg !143
  store i32 %t763, ptr %slot760, !dbg !143
  br label %if.end.241, !dbg !143
if.else.243:
  br label %if.end.241, !dbg !143
if.end.241:
  %t764 = load i32, ptr %slot35, !dbg !144
  %t765 = load i32, ptr %slot760, !dbg !144
  %t766 = getelementptr inbounds { ptr, i32, i32, i32, i32, [32 x i32] }, ptr %slot27, i32 0, i32 2, !dbg !144
  %t767 = load i32, ptr %t766, !dbg !144
  %t768 = getelementptr inbounds { ptr, i32, i32, i32, i32, [32 x i32] }, ptr %slot27, i32 0, i32 1, !dbg !144
  %t769 = load i32, ptr %t768, !dbg !144
  %t770 = icmp ugt i32 %t764, %t767, !dbg !144
  %t771 = icmp uge i32 %t764, %t769, !dbg !144
  %t772 = or i1 %t770, %t771, !dbg !144
  br i1 %t772, label %lua.raise.244, label %lua.ok.245, !prof !7, !dbg !144
lua.raise.244:
  %t773 = getelementptr inbounds ptr, ptr %t1, i64 11, !dbg !144
  %rt.raise.774 = load ptr, ptr %t773, !invariant.load !8, !dbg !144
  call void %rt.raise.774(ptr %L, i64 8) nomerge, !dbg !144
  unreachable, !dbg !144
lua.ok.245:
  %t775 = icmp eq i32 %t764, %t767, !dbg !144
  %t776 = add i32 %t767, 1, !dbg !144
  %t777 = select i1 %t775, i32 %t776, i32 %t767, !dbg !144
  store i32 %t777, ptr %t766, !dbg !144
  %t778 = getelementptr inbounds { ptr, i32, i32, i32, i32, [32 x i32] }, ptr %slot27, i32 0, i32 0, !dbg !144
  %t779 = load ptr, ptr %t778, !dbg !144
  %t780 = zext i32 %t764 to i64, !dbg !144
  %t781 = getelementptr inbounds i32, ptr %t779, i64 %t780, !dbg !144
  store i32 %t765, ptr %t781, !dbg !144
  store i1 false, ptr %slot36, !dbg !145
  br label %if.end.238, !dbg !145
if.else.240:
  %t782 = load i32, ptr %slot35, !dbg !146
  %t783 = load i32, ptr %slot615, !dbg !146
  %t784 = getelementptr inbounds { ptr, i32, i32, i32, i32, [32 x i32] }, ptr %slot27, i32 0, i32 2, !dbg !146
  %t785 = load i32, ptr %t784, !dbg !146
  %t786 = getelementptr inbounds { ptr, i32, i32, i32, i32, [32 x i32] }, ptr %slot27, i32 0, i32 1, !dbg !146
  %t787 = load i32, ptr %t786, !dbg !146
  %t788 = icmp ugt i32 %t782, %t785, !dbg !146
  %t789 = icmp uge i32 %t782, %t787, !dbg !146
  %t790 = or i1 %t788, %t789, !dbg !146
  br i1 %t790, label %lua.raise.246, label %lua.ok.247, !prof !7, !dbg !146
lua.raise.246:
  %t791 = getelementptr inbounds ptr, ptr %t1, i64 11, !dbg !146
  %rt.raise.792 = load ptr, ptr %t791, !invariant.load !8, !dbg !146
  call void %rt.raise.792(ptr %L, i64 8) nomerge, !dbg !146
  unreachable, !dbg !146
lua.ok.247:
  %t793 = icmp eq i32 %t782, %t785, !dbg !146
  %t794 = add i32 %t785, 1, !dbg !146
  %t795 = select i1 %t793, i32 %t794, i32 %t785, !dbg !146
  store i32 %t795, ptr %t784, !dbg !146
  %t796 = getelementptr inbounds { ptr, i32, i32, i32, i32, [32 x i32] }, ptr %slot27, i32 0, i32 0, !dbg !146
  %t797 = load ptr, ptr %t796, !dbg !146
  %t798 = zext i32 %t782 to i64, !dbg !146
  %t799 = getelementptr inbounds i32, ptr %t797, i64 %t798, !dbg !146
  store i32 %t783, ptr %t799, !dbg !146
  store i1 true, ptr %slot36, !dbg !147
  store i1 false, ptr %slot37, !dbg !148
  br label %if.end.238, !dbg !148
if.end.238:
  %t800 = load i32, ptr %slot35, !dbg !149
  %t801 = add i32 %t800, 1, !dbg !149
  store i32 %t801, ptr %slot35, !dbg !149
  br label %if.end.233, !dbg !149
if.else.237:
  %t802 = load i32, ptr %slot624, !dbg !149
  %t803 = icmp ult i32 %t802, 32, !dbg !149
  br i1 %t803, label %if.then.248, label %if.else.249, !dbg !149
if.then.248:
  %t804 = load i32, ptr %slot624, !dbg !150
  %t805 = icmp eq i32 %t804, 9, !dbg !150
  br i1 %t805, label %or.end.251, label %or.rhs.250, !dbg !150
or.rhs.250:
  %t806 = load i32, ptr %slot624, !dbg !150
  %t807 = icmp eq i32 %t806, 10, !dbg !150
  br label %or.end.251, !dbg !150
or.end.251:
  %t808 = phi i1 [ true, %if.then.248 ], [ %t807, %or.rhs.250 ], !dbg !150
  br i1 %t808, label %or.end.253, label %or.rhs.252, !dbg !150
or.rhs.252:
  %t809 = load i32, ptr %slot624, !dbg !150
  %t810 = icmp eq i32 %t809, 13, !dbg !150
  br label %or.end.253, !dbg !150
or.end.253:
  %t811 = phi i1 [ true, %or.end.251 ], [ %t810, %or.rhs.252 ], !dbg !150
  store i1 %t811, ptr %slot812, !dbg !150
  %t813 = load i1, ptr %slot36, !dbg !151
  br i1 %t813, label %or.end.256, label %or.rhs.255, !dbg !151
or.rhs.255:
  %t814 = load i1, ptr %slot812, !dbg !151
  %t815 = xor i1 %t814, true, !dbg !151
  br label %or.end.256, !dbg !151
or.end.256:
  %t816 = phi i1 [ true, %or.end.253 ], [ %t815, %or.rhs.255 ], !dbg !151
  br i1 %t816, label %if.then.257, label %if.else.258, !dbg !151
if.then.257:
  call void @lua_pushvalue(ptr %L, i32 2), !dbg !152
  %t817 = call i32 @nupp.wrap.u32(double 0x4008000000000000), !dbg !152
  %t818 = uitofp i32 %t817 to double, !dbg !152
  call void @lua_pushnumber(ptr %L, double %t818), !dbg !152
  %t819 = load i32, ptr %slot615, !dbg !152
  %t820 = add i32 %t819, 1, !dbg !152
  %t821 = uitofp i32 %t820 to double, !dbg !152
  call void @lua_pushnumber(ptr %L, double %t821), !dbg !152
  ret i32 3, !dbg !152
if.else.258:
  br label %if.end.254, !dbg !152
if.end.254:
  br label %if.end.233, !dbg !152
if.else.249:
  %t822 = load i1, ptr %slot36, !dbg !152
  %t823 = xor i1 %t822, true, !dbg !152
  br i1 %t823, label %if.then.259, label %if.else.260, !dbg !152
if.then.259:
  %t824 = load i32, ptr %slot35, !dbg !153
  %t825 = load i32, ptr %slot615, !dbg !153
  %t826 = getelementptr inbounds { ptr, i32, i32, i32, i32, [32 x i32] }, ptr %slot27, i32 0, i32 2, !dbg !153
  %t827 = load i32, ptr %t826, !dbg !153
  %t828 = getelementptr inbounds { ptr, i32, i32, i32, i32, [32 x i32] }, ptr %slot27, i32 0, i32 1, !dbg !153
  %t829 = load i32, ptr %t828, !dbg !153
  %t830 = icmp ugt i32 %t824, %t827, !dbg !153
  %t831 = icmp uge i32 %t824, %t829, !dbg !153
  %t832 = or i1 %t830, %t831, !dbg !153
  br i1 %t832, label %lua.raise.261, label %lua.ok.262, !prof !7, !dbg !153
lua.raise.261:
  %t833 = getelementptr inbounds ptr, ptr %t1, i64 11, !dbg !153
  %rt.raise.834 = load ptr, ptr %t833, !invariant.load !8, !dbg !153
  call void %rt.raise.834(ptr %L, i64 8) nomerge, !dbg !153
  unreachable, !dbg !153
lua.ok.262:
  %t835 = icmp eq i32 %t824, %t827, !dbg !153
  %t836 = add i32 %t827, 1, !dbg !153
  %t837 = select i1 %t835, i32 %t836, i32 %t827, !dbg !153
  store i32 %t837, ptr %t826, !dbg !153
  %t838 = getelementptr inbounds { ptr, i32, i32, i32, i32, [32 x i32] }, ptr %slot27, i32 0, i32 0, !dbg !153
  %t839 = load ptr, ptr %t838, !dbg !153
  %t840 = zext i32 %t824 to i64, !dbg !153
  %t841 = getelementptr inbounds i32, ptr %t839, i64 %t840, !dbg !153
  store i32 %t825, ptr %t841, !dbg !153
  %t842 = load i32, ptr %slot35, !dbg !154
  %t843 = add i32 %t842, 1, !dbg !154
  store i32 %t843, ptr %slot35, !dbg !154
  br label %if.end.233, !dbg !154
if.else.260:
  br label %if.end.233, !dbg !154
if.end.233:
  store i1 false, ptr %slot39, !dbg !155
  store i1 false, ptr %slot38, !dbg !156
  br label %if.end.171, !dbg !156
if.end.171:
  br label %if.end.161, !dbg !156
if.else.163:
  br label %if.end.161, !dbg !156
if.end.161:
  br label %while.head.158, !dbg !156
while.end.160:
  %t844 = load i32, ptr %slot33, !dbg !157
  %t845 = load i32, ptr %slot70, !dbg !157
  %t846 = add i32 %t844, %t845, !dbg !157
  store i32 %t846, ptr %slot33, !dbg !157
  br label %while.head.14, !dbg !157
while.end.16:
  br label %cursors.done.13, !dbg !157
cursors.narrow.12:
  br label %while.head.263, !dbg !157
while.head.263:
  %t847 = load i32, ptr %slot33, !dbg !157
  %t848 = load i32, ptr %slot20, !dbg !157
  %t849 = icmp ult i32 %t847, %t848, !dbg !157
  br i1 %t849, label %or.end.267, label %or.rhs.266, !dbg !157
or.rhs.266:
  %t850 = load i1, ptr %slot49, !dbg !157
  %t851 = xor i1 %t850, true, !dbg !157
  br label %or.end.267, !dbg !157
or.end.267:
  %t852 = phi i1 [ true, %while.head.263 ], [ %t851, %or.rhs.266 ], !dbg !157
  br i1 %t852, label %while.body.264, label %while.end.265, !dbg !157
while.body.264:
  %t853 = call i64 @llvm.fptosi.sat.i64.f64(double 0x0000000000000000), !dbg !29
  %t854 = call i64 @llvm.fptoui.sat.i64.f64(double 0x0000000000000000), !dbg !29
  %t855 = fcmp olt double 0x0000000000000000, 0.0, !dbg !29
  %t856 = select i1 %t855, i64 %t853, i64 %t854, !dbg !29
  store i64 %t856, ptr %slot68, !dbg !29
  %t857 = call i32 @nupp.wrap.u32(double 0x0000000000000000), !dbg !30
  store i32 %t857, ptr %slot70, !dbg !30
  br i1 true, label %if.then.269, label %if.else.270, !dbg !31
if.then.269:
  %t858 = load i1, ptr %slot56, !dbg !32
  %t859 = xor i1 %t858, true, !dbg !32
  br i1 %t859, label %and.rhs.272, label %and.end.273, !dbg !32
and.rhs.272:
  %t860 = load i32, ptr %slot33, !dbg !32
  %t861 = zext i32 %t860 to i64, !dbg !32
  %t862 = zext i32 16 to i64, !dbg !32
  %t863 = add i64 %t861, %t862, !dbg !32
  %t864 = load i32, ptr %slot20, !dbg !32
  %t865 = zext i32 %t864 to i64, !dbg !32
  %t866 = icmp ule i64 %t863, %t865, !dbg !32
  br label %and.end.273, !dbg !32
and.end.273:
  %t867 = phi i1 [ false, %if.then.269 ], [ %t866, %and.rhs.272 ], !dbg !32
  br i1 %t867, label %if.then.274, label %if.else.275, !dbg !32
if.then.274:
  %t868 = load i32, ptr %slot33, !dbg !33
  %t869 = zext i32 %t868 to i64, !dbg !33
  %t870 = add nuw i64 %t869, 16, !dbg !33
  %t871 = icmp ule i64 %t870, 4294967295, !dbg !33
  %t872 = add nuw i64 %t869, 0, !dbg !33
  %t873 = getelementptr inbounds nuw i8, ptr %t14, i64 %t872, !dbg !33
  br i1 %t871, label %simd.yes.276, label %simd.no.277, !dbg !33
simd.yes.276:
  %t874 = load <16 x i8>, ptr %t873, align 1, !dbg !33
  br label %simd.join.278, !dbg !33
simd.no.277:
  %t875 = load i32, ptr %slot33, !dbg !33
  %t876 = add i32 %t875, 1, !dbg !33
  %t877 = zext i32 %t876 to i64, !dbg !33
  %t878 = icmp ne i64 %t877, 0, !dbg !33
  %t879 = sub i64 %t877, 1, !dbg !33
  %t880 = select i1 %t878, i64 %t879, i64 -1, !dbg !33
  %t881 = icmp ult i64 %t880, %t15, !dbg !33
  %t882 = sub i64 %t15, %t880, !dbg !33
  %t883 = icmp ult i64 %t882, 16, !dbg !33
  %t884 = select i1 %t883, i64 %t882, i64 16, !dbg !33
  %t885 = select i1 %t881, i64 %t884, i64 0, !dbg !33
  %t886 = trunc i64 %t885 to i32, !dbg !33
  %t887 = select i1 %t881, i64 %t880, i64 0, !dbg !33
  %t888 = getelementptr inbounds i8, ptr %t14, i64 %t887, !dbg !33
  %t889 = icmp eq i32 %t886, 16, !dbg !33
  br i1 %t889, label %simd.yes.279, label %simd.no.280, !dbg !33
simd.yes.279:
  %t890 = load <16 x i8>, ptr %t888, align 1, !dbg !33
  br label %simd.join.281, !dbg !33
simd.no.280:
  switch i32 %t886, label %tail.done.298 [ i32 1, label %tail.lane.282 i32 2, label %tail.lane.283 i32 3, label %tail.lane.284 i32 4, label %tail.lane.285 i32 5, label %tail.lane.286 i32 6, label %tail.lane.287 i32 7, label %tail.lane.288 i32 8, label %tail.lane.289 i32 9, label %tail.lane.290 i32 10, label %tail.lane.291 i32 11, label %tail.lane.292 i32 12, label %tail.lane.293 i32 13, label %tail.lane.294 i32 14, label %tail.lane.295 i32 15, label %tail.lane.296 i32 16, label %tail.lane.297 ], !dbg !33
tail.lane.297:
  %t891 = getelementptr inbounds i8, ptr %t888, i64 15, !dbg !33
  %t892 = load i8, ptr %t891, align 1, !dbg !33
  %t893 = insertelement <16 x i8> zeroinitializer, i8 %t892, i32 15, !dbg !33
  br label %tail.lane.296, !dbg !33
tail.lane.296:
  %t894 = phi <16 x i8> [ zeroinitializer, %simd.no.280 ], [ %t893, %tail.lane.297 ], !dbg !33
  %t895 = getelementptr inbounds i8, ptr %t888, i64 14, !dbg !33
  %t896 = load i8, ptr %t895, align 1, !dbg !33
  %t897 = insertelement <16 x i8> %t894, i8 %t896, i32 14, !dbg !33
  br label %tail.lane.295, !dbg !33
tail.lane.295:
  %t898 = phi <16 x i8> [ zeroinitializer, %simd.no.280 ], [ %t897, %tail.lane.296 ], !dbg !33
  %t899 = getelementptr inbounds i8, ptr %t888, i64 13, !dbg !33
  %t900 = load i8, ptr %t899, align 1, !dbg !33
  %t901 = insertelement <16 x i8> %t898, i8 %t900, i32 13, !dbg !33
  br label %tail.lane.294, !dbg !33
tail.lane.294:
  %t902 = phi <16 x i8> [ zeroinitializer, %simd.no.280 ], [ %t901, %tail.lane.295 ], !dbg !33
  %t903 = getelementptr inbounds i8, ptr %t888, i64 12, !dbg !33
  %t904 = load i8, ptr %t903, align 1, !dbg !33
  %t905 = insertelement <16 x i8> %t902, i8 %t904, i32 12, !dbg !33
  br label %tail.lane.293, !dbg !33
tail.lane.293:
  %t906 = phi <16 x i8> [ zeroinitializer, %simd.no.280 ], [ %t905, %tail.lane.294 ], !dbg !33
  %t907 = getelementptr inbounds i8, ptr %t888, i64 11, !dbg !33
  %t908 = load i8, ptr %t907, align 1, !dbg !33
  %t909 = insertelement <16 x i8> %t906, i8 %t908, i32 11, !dbg !33
  br label %tail.lane.292, !dbg !33
tail.lane.292:
  %t910 = phi <16 x i8> [ zeroinitializer, %simd.no.280 ], [ %t909, %tail.lane.293 ], !dbg !33
  %t911 = getelementptr inbounds i8, ptr %t888, i64 10, !dbg !33
  %t912 = load i8, ptr %t911, align 1, !dbg !33
  %t913 = insertelement <16 x i8> %t910, i8 %t912, i32 10, !dbg !33
  br label %tail.lane.291, !dbg !33
tail.lane.291:
  %t914 = phi <16 x i8> [ zeroinitializer, %simd.no.280 ], [ %t913, %tail.lane.292 ], !dbg !33
  %t915 = getelementptr inbounds i8, ptr %t888, i64 9, !dbg !33
  %t916 = load i8, ptr %t915, align 1, !dbg !33
  %t917 = insertelement <16 x i8> %t914, i8 %t916, i32 9, !dbg !33
  br label %tail.lane.290, !dbg !33
tail.lane.290:
  %t918 = phi <16 x i8> [ zeroinitializer, %simd.no.280 ], [ %t917, %tail.lane.291 ], !dbg !33
  %t919 = getelementptr inbounds i8, ptr %t888, i64 8, !dbg !33
  %t920 = load i8, ptr %t919, align 1, !dbg !33
  %t921 = insertelement <16 x i8> %t918, i8 %t920, i32 8, !dbg !33
  br label %tail.lane.289, !dbg !33
tail.lane.289:
  %t922 = phi <16 x i8> [ zeroinitializer, %simd.no.280 ], [ %t921, %tail.lane.290 ], !dbg !33
  %t923 = getelementptr inbounds i8, ptr %t888, i64 7, !dbg !33
  %t924 = load i8, ptr %t923, align 1, !dbg !33
  %t925 = insertelement <16 x i8> %t922, i8 %t924, i32 7, !dbg !33
  br label %tail.lane.288, !dbg !33
tail.lane.288:
  %t926 = phi <16 x i8> [ zeroinitializer, %simd.no.280 ], [ %t925, %tail.lane.289 ], !dbg !33
  %t927 = getelementptr inbounds i8, ptr %t888, i64 6, !dbg !33
  %t928 = load i8, ptr %t927, align 1, !dbg !33
  %t929 = insertelement <16 x i8> %t926, i8 %t928, i32 6, !dbg !33
  br label %tail.lane.287, !dbg !33
tail.lane.287:
  %t930 = phi <16 x i8> [ zeroinitializer, %simd.no.280 ], [ %t929, %tail.lane.288 ], !dbg !33
  %t931 = getelementptr inbounds i8, ptr %t888, i64 5, !dbg !33
  %t932 = load i8, ptr %t931, align 1, !dbg !33
  %t933 = insertelement <16 x i8> %t930, i8 %t932, i32 5, !dbg !33
  br label %tail.lane.286, !dbg !33
tail.lane.286:
  %t934 = phi <16 x i8> [ zeroinitializer, %simd.no.280 ], [ %t933, %tail.lane.287 ], !dbg !33
  %t935 = getelementptr inbounds i8, ptr %t888, i64 4, !dbg !33
  %t936 = load i8, ptr %t935, align 1, !dbg !33
  %t937 = insertelement <16 x i8> %t934, i8 %t936, i32 4, !dbg !33
  br label %tail.lane.285, !dbg !33
tail.lane.285:
  %t938 = phi <16 x i8> [ zeroinitializer, %simd.no.280 ], [ %t937, %tail.lane.286 ], !dbg !33
  %t939 = getelementptr inbounds i8, ptr %t888, i64 3, !dbg !33
  %t940 = load i8, ptr %t939, align 1, !dbg !33
  %t941 = insertelement <16 x i8> %t938, i8 %t940, i32 3, !dbg !33
  br label %tail.lane.284, !dbg !33
tail.lane.284:
  %t942 = phi <16 x i8> [ zeroinitializer, %simd.no.280 ], [ %t941, %tail.lane.285 ], !dbg !33
  %t943 = getelementptr inbounds i8, ptr %t888, i64 2, !dbg !33
  %t944 = load i8, ptr %t943, align 1, !dbg !33
  %t945 = insertelement <16 x i8> %t942, i8 %t944, i32 2, !dbg !33
  br label %tail.lane.283, !dbg !33
tail.lane.283:
  %t946 = phi <16 x i8> [ zeroinitializer, %simd.no.280 ], [ %t945, %tail.lane.284 ], !dbg !33
  %t947 = getelementptr inbounds i8, ptr %t888, i64 1, !dbg !33
  %t948 = load i8, ptr %t947, align 1, !dbg !33
  %t949 = insertelement <16 x i8> %t946, i8 %t948, i32 1, !dbg !33
  br label %tail.lane.282, !dbg !33
tail.lane.282:
  %t950 = phi <16 x i8> [ zeroinitializer, %simd.no.280 ], [ %t949, %tail.lane.283 ], !dbg !33
  %t951 = getelementptr inbounds i8, ptr %t888, i64 0, !dbg !33
  %t952 = load i8, ptr %t951, align 1, !dbg !33
  %t953 = insertelement <16 x i8> %t950, i8 %t952, i32 0, !dbg !33
  br label %tail.done.298, !dbg !33
tail.done.298:
  %t954 = phi <16 x i8> [ zeroinitializer, %simd.no.280 ], [ %t953, %tail.lane.282 ], !dbg !33
  br label %simd.join.281, !dbg !33
simd.join.281:
  %t955 = phi <16 x i8> [ %t890, %simd.yes.279 ], [ %t954, %tail.done.298 ], !dbg !33
  br label %simd.join.278, !dbg !33
simd.join.278:
  %t956 = phi <16 x i8> [ %t874, %simd.yes.276 ], [ %t955, %simd.join.281 ], !dbg !33
  store <16 x i8> %t956, ptr %slot168, !dbg !33
  %t957 = load <16 x i8>, ptr %slot168, !dbg !34
  %t958 = call i32 @nupp.wrap.u32(double 0x405EC00000000000), !dbg !34
  %t959 = trunc i32 %t958 to i8, !dbg !34
  %t960 = insertelement <16 x i8> poison, i8 %t959, i64 0, !dbg !34
  %t961 = shufflevector <16 x i8> %t960, <16 x i8> poison, <16 x i32> zeroinitializer, !dbg !34
  %t962 = icmp eq <16 x i8> %t957, %t961, !dbg !34
  %t963 = load <16 x i8>, ptr %slot168, !dbg !34
  %t964 = call i32 @nupp.wrap.u32(double 0x405F400000000000), !dbg !34
  %t965 = trunc i32 %t964 to i8, !dbg !34
  %t966 = insertelement <16 x i8> poison, i8 %t965, i64 0, !dbg !34
  %t967 = shufflevector <16 x i8> %t966, <16 x i8> poison, <16 x i32> zeroinitializer, !dbg !34
  %t968 = icmp eq <16 x i8> %t963, %t967, !dbg !34
  %t969 = or <16 x i1> %t962, %t968, !dbg !34
  %t970 = load <16 x i8>, ptr %slot168, !dbg !34
  %t971 = call i32 @nupp.wrap.u32(double 0x4056C00000000000), !dbg !34
  %t972 = trunc i32 %t971 to i8, !dbg !34
  %t973 = insertelement <16 x i8> poison, i8 %t972, i64 0, !dbg !34
  %t974 = shufflevector <16 x i8> %t973, <16 x i8> poison, <16 x i32> zeroinitializer, !dbg !34
  %t975 = icmp eq <16 x i8> %t970, %t974, !dbg !34
  %t976 = or <16 x i1> %t969, %t975, !dbg !34
  %t977 = load <16 x i8>, ptr %slot168, !dbg !34
  %t978 = call i32 @nupp.wrap.u32(double 0x4057400000000000), !dbg !34
  %t979 = trunc i32 %t978 to i8, !dbg !34
  %t980 = insertelement <16 x i8> poison, i8 %t979, i64 0, !dbg !34
  %t981 = shufflevector <16 x i8> %t980, <16 x i8> poison, <16 x i32> zeroinitializer, !dbg !34
  %t982 = icmp eq <16 x i8> %t977, %t981, !dbg !34
  %t983 = or <16 x i1> %t976, %t982, !dbg !34
  store <16 x i1> %t983, ptr %slot196, !dbg !34
  %t984 = load <16 x i8>, ptr %slot168, !dbg !35
  %t985 = call i32 @nupp.wrap.u32(double 0x404D000000000000), !dbg !35
  %t986 = trunc i32 %t985 to i8, !dbg !35
  %t987 = insertelement <16 x i8> poison, i8 %t986, i64 0, !dbg !35
  %t988 = shufflevector <16 x i8> %t987, <16 x i8> poison, <16 x i32> zeroinitializer, !dbg !35
  %t989 = icmp eq <16 x i8> %t984, %t988, !dbg !35
  %t990 = load <16 x i8>, ptr %slot168, !dbg !35
  %t991 = call i32 @nupp.wrap.u32(double 0x4046000000000000), !dbg !35
  %t992 = trunc i32 %t991 to i8, !dbg !35
  %t993 = insertelement <16 x i8> poison, i8 %t992, i64 0, !dbg !35
  %t994 = shufflevector <16 x i8> %t993, <16 x i8> poison, <16 x i32> zeroinitializer, !dbg !35
  %t995 = icmp eq <16 x i8> %t990, %t994, !dbg !35
  %t996 = or <16 x i1> %t989, %t995, !dbg !35
  store <16 x i1> %t996, ptr %slot210, !dbg !35
  %t997 = load <16 x i8>, ptr %slot168, !dbg !36
  %t998 = call i32 @nupp.wrap.u32(double 0x4041000000000000), !dbg !36
  %t999 = trunc i32 %t998 to i8, !dbg !36
  %t1000 = insertelement <16 x i8> poison, i8 %t999, i64 0, !dbg !36
  %t1001 = shufflevector <16 x i8> %t1000, <16 x i8> poison, <16 x i32> zeroinitializer, !dbg !36
  %t1002 = icmp eq <16 x i8> %t997, %t1001, !dbg !36
  %t1003 = load <16 x i8>, ptr %slot168, !dbg !36
  %t1004 = call i32 @nupp.wrap.u32(double 0x4057000000000000), !dbg !36
  %t1005 = trunc i32 %t1004 to i8, !dbg !36
  %t1006 = insertelement <16 x i8> poison, i8 %t1005, i64 0, !dbg !36
  %t1007 = shufflevector <16 x i8> %t1006, <16 x i8> poison, <16 x i32> zeroinitializer, !dbg !36
  %t1008 = icmp eq <16 x i8> %t1003, %t1007, !dbg !36
  %t1009 = or <16 x i1> %t1002, %t1008, !dbg !36
  store <16 x i1> %t1009, ptr %slot224, !dbg !36
  %t1010 = load <16 x i1>, ptr %slot196, !dbg !37
  %t1011 = load <16 x i1>, ptr %slot210, !dbg !37
  %t1012 = or <16 x i1> %t1010, %t1011, !dbg !37
  %t1013 = load <16 x i1>, ptr %slot224, !dbg !37
  %t1014 = or <16 x i1> %t1012, %t1013, !dbg !37
  %t1015 = load <16 x i8>, ptr %slot168, !dbg !37
  %t1016 = call i32 @nupp.wrap.u32(double 0x4040000000000000), !dbg !37
  %t1017 = trunc i32 %t1016 to i8, !dbg !37
  %t1018 = insertelement <16 x i8> poison, i8 %t1017, i64 0, !dbg !37
  %t1019 = shufflevector <16 x i8> %t1018, <16 x i8> poison, <16 x i32> zeroinitializer, !dbg !37
  %t1020 = icmp ult <16 x i8> %t1015, %t1019, !dbg !37
  %t1021 = or <16 x i1> %t1014, %t1020, !dbg !37
  store <16 x i1> %t1021, ptr %slot237, !dbg !37
  store i1 false, ptr %slot238, !dbg !38
  %t1022 = load i1, ptr %slot50, !dbg !39
  br i1 %t1022, label %if.then.300, label %if.else.301, !dbg !39
if.then.300:
  %t1023 = load <16 x i1>, ptr %slot237, !dbg !40
  %t1024 = bitcast <16 x i1> %t1023 to i16, !dbg !40
  %t1025 = zext i16 %t1024 to i64, !dbg !40
  store i64 %t1025, ptr %slot68, !dbg !40
  store i1 true, ptr %slot238, !dbg !41
  br label %if.end.299, !dbg !41
if.else.301:
  %t1026 = load <16 x i8>, ptr %slot168, !dbg !42
  %t1027 = call i32 @nupp.wrap.u32(double 0x4060000000000000), !dbg !42
  %t1028 = trunc i32 %t1027 to i8, !dbg !42
  %t1029 = insertelement <16 x i8> poison, i8 %t1028, i64 0, !dbg !42
  %t1030 = shufflevector <16 x i8> %t1029, <16 x i8> poison, <16 x i32> zeroinitializer, !dbg !42
  %t1031 = icmp uge <16 x i8> %t1026, %t1030, !dbg !42
  store <16 x i1> %t1031, ptr %slot249, !dbg !42
  %t1032 = load <16 x i1>, ptr %slot237, !dbg !43
  %t1033 = load <16 x i1>, ptr %slot249, !dbg !43
  %t1034 = or <16 x i1> %t1032, %t1033, !dbg !43
  %t1035 = bitcast <16 x i1> %t1034 to i16, !dbg !43
  %t1036 = zext i16 %t1035 to i64, !dbg !43
  store i64 %t1036, ptr %slot68, !dbg !43
  %t1037 = load i64, ptr %slot68, !dbg !44
  %t1038 = call i64 @llvm.fptosi.sat.i64.f64(double 0x0000000000000000), !dbg !44
  %t1039 = call i64 @llvm.fptoui.sat.i64.f64(double 0x0000000000000000), !dbg !44
  %t1040 = fcmp olt double 0x0000000000000000, 0.0, !dbg !44
  %t1041 = select i1 %t1040, i64 %t1038, i64 %t1039, !dbg !44
  %t1042 = icmp ne i64 %t1037, %t1041, !dbg !44
  br i1 %t1042, label %if.then.303, label %if.else.304, !dbg !44
if.then.303:
  %t1043 = load <16 x i1>, ptr %slot249, !dbg !45
  %t1044 = sext <16 x i1> %t1043 to <16 x i8>, !dbg !45
  %t1045 = call <16 x i8> asm "", "=w,0"(<16 x i8> %t1044), !dbg !45
  %t1046 = bitcast <16 x i8> %t1045 to <4 x i32>, !dbg !45
  %t1047 = shufflevector <4 x i32> %t1046, <4 x i32> poison, <4 x i32> <i32 0, i32 1, i32 2, i32 3>, !dbg !45
  %t1048 = call <4 x i32> @llvm.aarch64.neon.umaxp.v4i32(<4 x i32> %t1047, <4 x i32> %t1047), !dbg !45
  %t1049 = bitcast <4 x i32> %t1048 to <2 x i64>, !dbg !45
  %t1050 = extractelement <2 x i64> %t1049, i32 0, !dbg !45
  %t1051 = icmp ne i64 %t1050, 0, !dbg !45
  store i1 %t1051, ptr %slot238, !dbg !45
  %t1052 = load i1, ptr %slot238, !dbg !46
  br i1 %t1052, label %if.then.306, label %if.else.307, !dbg !46
if.then.306:
  %t1053 = load <16 x i1>, ptr %slot237, !dbg !47
  %t1054 = bitcast <16 x i1> %t1053 to i16, !dbg !47
  %t1055 = zext i16 %t1054 to i64, !dbg !47
  store i64 %t1055, ptr %slot68, !dbg !47
  br label %if.end.305, !dbg !47
if.else.307:
  br label %if.end.305, !dbg !47
if.end.305:
  br label %if.end.302, !dbg !47
if.else.304:
  br label %if.end.302, !dbg !47
if.end.302:
  br label %if.end.299, !dbg !47
if.end.299:
  %t1056 = load i1, ptr %slot238, !dbg !48
  br i1 %t1056, label %if.then.309, label %if.else.310, !dbg !48
if.then.309:
  %t1057 = load i32, ptr %slot33, !dbg !49
  %t1058 = sub i32 %t1057, 16, !dbg !49
  %t1059 = add i32 %t1058, 1, !dbg !49
  %t1060 = zext i32 %t1059 to i64, !dbg !49
  %t1061 = icmp ne i64 %t1060, 0, !dbg !49
  %t1062 = sub i64 %t1060, 1, !dbg !49
  %t1063 = select i1 %t1061, i64 %t1062, i64 -1, !dbg !49
  %t1064 = icmp ult i64 %t1063, %t15, !dbg !49
  %t1065 = sub i64 %t15, %t1063, !dbg !49
  %t1066 = icmp ult i64 %t1065, 16, !dbg !49
  %t1067 = select i1 %t1066, i64 %t1065, i64 16, !dbg !49
  %t1068 = select i1 %t1064, i64 %t1067, i64 0, !dbg !49
  %t1069 = trunc i64 %t1068 to i32, !dbg !49
  %t1070 = select i1 %t1064, i64 %t1063, i64 0, !dbg !49
  %t1071 = getelementptr inbounds i8, ptr %t14, i64 %t1070, !dbg !49
  %t1072 = icmp eq i32 %t1069, 16, !dbg !49
  br i1 %t1072, label %simd.yes.311, label %simd.no.312, !dbg !49
simd.yes.311:
  %t1073 = load <16 x i8>, ptr %t1071, align 1, !dbg !49
  br label %simd.join.313, !dbg !49
simd.no.312:
  switch i32 %t1069, label %tail.done.330 [ i32 1, label %tail.lane.314 i32 2, label %tail.lane.315 i32 3, label %tail.lane.316 i32 4, label %tail.lane.317 i32 5, label %tail.lane.318 i32 6, label %tail.lane.319 i32 7, label %tail.lane.320 i32 8, label %tail.lane.321 i32 9, label %tail.lane.322 i32 10, label %tail.lane.323 i32 11, label %tail.lane.324 i32 12, label %tail.lane.325 i32 13, label %tail.lane.326 i32 14, label %tail.lane.327 i32 15, label %tail.lane.328 i32 16, label %tail.lane.329 ], !dbg !49
tail.lane.329:
  %t1074 = getelementptr inbounds i8, ptr %t1071, i64 15, !dbg !49
  %t1075 = load i8, ptr %t1074, align 1, !dbg !49
  %t1076 = insertelement <16 x i8> zeroinitializer, i8 %t1075, i32 15, !dbg !49
  br label %tail.lane.328, !dbg !49
tail.lane.328:
  %t1077 = phi <16 x i8> [ zeroinitializer, %simd.no.312 ], [ %t1076, %tail.lane.329 ], !dbg !49
  %t1078 = getelementptr inbounds i8, ptr %t1071, i64 14, !dbg !49
  %t1079 = load i8, ptr %t1078, align 1, !dbg !49
  %t1080 = insertelement <16 x i8> %t1077, i8 %t1079, i32 14, !dbg !49
  br label %tail.lane.327, !dbg !49
tail.lane.327:
  %t1081 = phi <16 x i8> [ zeroinitializer, %simd.no.312 ], [ %t1080, %tail.lane.328 ], !dbg !49
  %t1082 = getelementptr inbounds i8, ptr %t1071, i64 13, !dbg !49
  %t1083 = load i8, ptr %t1082, align 1, !dbg !49
  %t1084 = insertelement <16 x i8> %t1081, i8 %t1083, i32 13, !dbg !49
  br label %tail.lane.326, !dbg !49
tail.lane.326:
  %t1085 = phi <16 x i8> [ zeroinitializer, %simd.no.312 ], [ %t1084, %tail.lane.327 ], !dbg !49
  %t1086 = getelementptr inbounds i8, ptr %t1071, i64 12, !dbg !49
  %t1087 = load i8, ptr %t1086, align 1, !dbg !49
  %t1088 = insertelement <16 x i8> %t1085, i8 %t1087, i32 12, !dbg !49
  br label %tail.lane.325, !dbg !49
tail.lane.325:
  %t1089 = phi <16 x i8> [ zeroinitializer, %simd.no.312 ], [ %t1088, %tail.lane.326 ], !dbg !49
  %t1090 = getelementptr inbounds i8, ptr %t1071, i64 11, !dbg !49
  %t1091 = load i8, ptr %t1090, align 1, !dbg !49
  %t1092 = insertelement <16 x i8> %t1089, i8 %t1091, i32 11, !dbg !49
  br label %tail.lane.324, !dbg !49
tail.lane.324:
  %t1093 = phi <16 x i8> [ zeroinitializer, %simd.no.312 ], [ %t1092, %tail.lane.325 ], !dbg !49
  %t1094 = getelementptr inbounds i8, ptr %t1071, i64 10, !dbg !49
  %t1095 = load i8, ptr %t1094, align 1, !dbg !49
  %t1096 = insertelement <16 x i8> %t1093, i8 %t1095, i32 10, !dbg !49
  br label %tail.lane.323, !dbg !49
tail.lane.323:
  %t1097 = phi <16 x i8> [ zeroinitializer, %simd.no.312 ], [ %t1096, %tail.lane.324 ], !dbg !49
  %t1098 = getelementptr inbounds i8, ptr %t1071, i64 9, !dbg !49
  %t1099 = load i8, ptr %t1098, align 1, !dbg !49
  %t1100 = insertelement <16 x i8> %t1097, i8 %t1099, i32 9, !dbg !49
  br label %tail.lane.322, !dbg !49
tail.lane.322:
  %t1101 = phi <16 x i8> [ zeroinitializer, %simd.no.312 ], [ %t1100, %tail.lane.323 ], !dbg !49
  %t1102 = getelementptr inbounds i8, ptr %t1071, i64 8, !dbg !49
  %t1103 = load i8, ptr %t1102, align 1, !dbg !49
  %t1104 = insertelement <16 x i8> %t1101, i8 %t1103, i32 8, !dbg !49
  br label %tail.lane.321, !dbg !49
tail.lane.321:
  %t1105 = phi <16 x i8> [ zeroinitializer, %simd.no.312 ], [ %t1104, %tail.lane.322 ], !dbg !49
  %t1106 = getelementptr inbounds i8, ptr %t1071, i64 7, !dbg !49
  %t1107 = load i8, ptr %t1106, align 1, !dbg !49
  %t1108 = insertelement <16 x i8> %t1105, i8 %t1107, i32 7, !dbg !49
  br label %tail.lane.320, !dbg !49
tail.lane.320:
  %t1109 = phi <16 x i8> [ zeroinitializer, %simd.no.312 ], [ %t1108, %tail.lane.321 ], !dbg !49
  %t1110 = getelementptr inbounds i8, ptr %t1071, i64 6, !dbg !49
  %t1111 = load i8, ptr %t1110, align 1, !dbg !49
  %t1112 = insertelement <16 x i8> %t1109, i8 %t1111, i32 6, !dbg !49
  br label %tail.lane.319, !dbg !49
tail.lane.319:
  %t1113 = phi <16 x i8> [ zeroinitializer, %simd.no.312 ], [ %t1112, %tail.lane.320 ], !dbg !49
  %t1114 = getelementptr inbounds i8, ptr %t1071, i64 5, !dbg !49
  %t1115 = load i8, ptr %t1114, align 1, !dbg !49
  %t1116 = insertelement <16 x i8> %t1113, i8 %t1115, i32 5, !dbg !49
  br label %tail.lane.318, !dbg !49
tail.lane.318:
  %t1117 = phi <16 x i8> [ zeroinitializer, %simd.no.312 ], [ %t1116, %tail.lane.319 ], !dbg !49
  %t1118 = getelementptr inbounds i8, ptr %t1071, i64 4, !dbg !49
  %t1119 = load i8, ptr %t1118, align 1, !dbg !49
  %t1120 = insertelement <16 x i8> %t1117, i8 %t1119, i32 4, !dbg !49
  br label %tail.lane.317, !dbg !49
tail.lane.317:
  %t1121 = phi <16 x i8> [ zeroinitializer, %simd.no.312 ], [ %t1120, %tail.lane.318 ], !dbg !49
  %t1122 = getelementptr inbounds i8, ptr %t1071, i64 3, !dbg !49
  %t1123 = load i8, ptr %t1122, align 1, !dbg !49
  %t1124 = insertelement <16 x i8> %t1121, i8 %t1123, i32 3, !dbg !49
  br label %tail.lane.316, !dbg !49
tail.lane.316:
  %t1125 = phi <16 x i8> [ zeroinitializer, %simd.no.312 ], [ %t1124, %tail.lane.317 ], !dbg !49
  %t1126 = getelementptr inbounds i8, ptr %t1071, i64 2, !dbg !49
  %t1127 = load i8, ptr %t1126, align 1, !dbg !49
  %t1128 = insertelement <16 x i8> %t1125, i8 %t1127, i32 2, !dbg !49
  br label %tail.lane.315, !dbg !49
tail.lane.315:
  %t1129 = phi <16 x i8> [ zeroinitializer, %simd.no.312 ], [ %t1128, %tail.lane.316 ], !dbg !49
  %t1130 = getelementptr inbounds i8, ptr %t1071, i64 1, !dbg !49
  %t1131 = load i8, ptr %t1130, align 1, !dbg !49
  %t1132 = insertelement <16 x i8> %t1129, i8 %t1131, i32 1, !dbg !49
  br label %tail.lane.314, !dbg !49
tail.lane.314:
  %t1133 = phi <16 x i8> [ zeroinitializer, %simd.no.312 ], [ %t1132, %tail.lane.315 ], !dbg !49
  %t1134 = getelementptr inbounds i8, ptr %t1071, i64 0, !dbg !49
  %t1135 = load i8, ptr %t1134, align 1, !dbg !49
  %t1136 = insertelement <16 x i8> %t1133, i8 %t1135, i32 0, !dbg !49
  br label %tail.done.330, !dbg !49
tail.done.330:
  %t1137 = phi <16 x i8> [ zeroinitializer, %simd.no.312 ], [ %t1136, %tail.lane.314 ], !dbg !49
  br label %simd.join.313, !dbg !49
simd.join.313:
  %t1138 = phi <16 x i8> [ %t1073, %simd.yes.311 ], [ %t1137, %tail.done.330 ], !dbg !49
  store <16 x i8> %t1138, ptr %slot357, !dbg !49
  %t1139 = load <16 x i8>, ptr %slot357, !dbg !50
  %t1140 = load <16 x i8>, ptr %slot168, !dbg !50
  %t1141 = shufflevector <16 x i8> %t1139, <16 x i8> %t1140, <16 x i32> <i32 15, i32 16, i32 17, i32 18, i32 19, i32 20, i32 21, i32 22, i32 23, i32 24, i32 25, i32 26, i32 27, i32 28, i32 29, i32 30>, !dbg !50
  store <16 x i8> %t1141, ptr %slot361, !dbg !50
  %t1142 = load <16 x i8>, ptr %slot357, !dbg !51
  %t1143 = load <16 x i8>, ptr %slot168, !dbg !51
  %t1144 = shufflevector <16 x i8> %t1142, <16 x i8> %t1143, <16 x i32> <i32 14, i32 15, i32 16, i32 17, i32 18, i32 19, i32 20, i32 21, i32 22, i32 23, i32 24, i32 25, i32 26, i32 27, i32 28, i32 29>, !dbg !51
  store <16 x i8> %t1144, ptr %slot365, !dbg !51
  %t1145 = load <16 x i8>, ptr %slot357, !dbg !52
  %t1146 = load <16 x i8>, ptr %slot168, !dbg !52
  %t1147 = shufflevector <16 x i8> %t1145, <16 x i8> %t1146, <16 x i32> <i32 13, i32 14, i32 15, i32 16, i32 17, i32 18, i32 19, i32 20, i32 21, i32 22, i32 23, i32 24, i32 25, i32 26, i32 27, i32 28>, !dbg !52
  store <16 x i8> %t1147, ptr %slot369, !dbg !52
  %t1148 = call i32 @nupp.wrap.u32(double 0x0000000000000000), !dbg !53
  %t1149 = trunc i32 %t1148 to i8, !dbg !53
  %t1150 = insertelement <16 x i8> poison, i8 %t1149, i64 0, !dbg !53
  %t1151 = shufflevector <16 x i8> %t1150, <16 x i8> poison, <16 x i32> zeroinitializer, !dbg !53
  store <16 x i8> %t1151, ptr %slot374, !dbg !53
  %t1152 = load <16 x i8>, ptr %slot374, !dbg !54
  %t1153 = call <16 x i8> @ks___nupp_const_decode_fused_24f677cbe166e03f__5f5f6e757070436f6e73745f6465636f646546757365645f32346636373763626531363665303366_helper_nibble_table(<16 x i8> %t1152, i32 2, i32 2, i32 2, i32 2, i32 2, i32 2, i32 2, i32 2, i32 128, i32 128, i32 128, i32 128, i32 33, i32 1, i32 21, i32 73), !dbg !54
  store <16 x i8> %t1153, ptr %slot377, !dbg !54
  %t1154 = load <16 x i8>, ptr %slot374, !dbg !55
  %t1155 = call <16 x i8> @ks___nupp_const_decode_fused_24f677cbe166e03f__5f5f6e757070436f6e73745f6465636f646546757365645f32346636373763626531363665303366_helper_nibble_table(<16 x i8> %t1154, i32 231, i32 163, i32 131, i32 131, i32 139, i32 203, i32 203, i32 203, i32 203, i32 203, i32 203, i32 203, i32 203, i32 219, i32 203, i32 203), !dbg !55
  store <16 x i8> %t1155, ptr %slot380, !dbg !55
  %t1156 = load <16 x i8>, ptr %slot374, !dbg !56
  %t1157 = call <16 x i8> @ks___nupp_const_decode_fused_24f677cbe166e03f__5f5f6e757070436f6e73745f6465636f646546757365645f32346636373763626531363665303366_helper_nibble_table(<16 x i8> %t1156, i32 1, i32 1, i32 1, i32 1, i32 1, i32 1, i32 1, i32 1, i32 230, i32 174, i32 186, i32 186, i32 1, i32 1, i32 1, i32 1), !dbg !56
  store <16 x i8> %t1157, ptr %slot383, !dbg !56
  %t1158 = load <16 x i8>, ptr %slot377, !dbg !57
  %t1159 = load <16 x i8>, ptr %slot361, !dbg !57
  %t1160 = call i32 @nupp.wrap.u32(double 0x4010000000000000), !dbg !57
  %t1161 = trunc i32 %t1160 to i8, !dbg !57
  %t1162 = insertelement <16 x i8> poison, i8 %t1161, i64 0, !dbg !57
  %t1163 = shufflevector <16 x i8> %t1162, <16 x i8> poison, <16 x i32> zeroinitializer, !dbg !57
  %t1164 = and <16 x i8> %t1163, splat (i8 7), !dbg !57
  %t1165 = lshr <16 x i8> %t1159, %t1164, !dbg !57
  %t1166 = call i32 @nupp.wrap.u32(double 0x3FF0000000000000), !dbg !57
  %t1167 = trunc i32 %t1166 to i8, !dbg !57
  %t1168 = insertelement <16 x i8> poison, i8 %t1167, i64 0, !dbg !57
  %t1169 = shufflevector <16 x i8> %t1168, <16 x i8> poison, <16 x i32> zeroinitializer, !dbg !57
  %t1170 = add <16 x i8> %t1165, %t1169, !dbg !57
  %t1171 = sub <16 x i8> %t1170, splat (i8 1), !dbg !57
  %t1172 = call <16 x i8> @llvm.aarch64.neon.tbl1.v16i8(<16 x i8> %t1158, <16 x i8> %t1171), !dbg !57
  %t1173 = load <16 x i8>, ptr %slot380, !dbg !57
  %t1174 = load <16 x i8>, ptr %slot361, !dbg !57
  %t1175 = call i32 @nupp.wrap.u32(double 0x402E000000000000), !dbg !57
  %t1176 = trunc i32 %t1175 to i8, !dbg !57
  %t1177 = insertelement <16 x i8> poison, i8 %t1176, i64 0, !dbg !57
  %t1178 = shufflevector <16 x i8> %t1177, <16 x i8> poison, <16 x i32> zeroinitializer, !dbg !57
  %t1179 = and <16 x i8> %t1174, %t1178, !dbg !57
  %t1180 = call i32 @nupp.wrap.u32(double 0x3FF0000000000000), !dbg !57
  %t1181 = trunc i32 %t1180 to i8, !dbg !57
  %t1182 = insertelement <16 x i8> poison, i8 %t1181, i64 0, !dbg !57
  %t1183 = shufflevector <16 x i8> %t1182, <16 x i8> poison, <16 x i32> zeroinitializer, !dbg !57
  %t1184 = add <16 x i8> %t1179, %t1183, !dbg !57
  %t1185 = sub <16 x i8> %t1184, splat (i8 1), !dbg !57
  %t1186 = call <16 x i8> @llvm.aarch64.neon.tbl1.v16i8(<16 x i8> %t1173, <16 x i8> %t1185), !dbg !57
  %t1187 = and <16 x i8> %t1172, %t1186, !dbg !57
  %t1188 = load <16 x i8>, ptr %slot383, !dbg !57
  %t1189 = load <16 x i8>, ptr %slot168, !dbg !57
  %t1190 = call i32 @nupp.wrap.u32(double 0x4010000000000000), !dbg !57
  %t1191 = trunc i32 %t1190 to i8, !dbg !57
  %t1192 = insertelement <16 x i8> poison, i8 %t1191, i64 0, !dbg !57
  %t1193 = shufflevector <16 x i8> %t1192, <16 x i8> poison, <16 x i32> zeroinitializer, !dbg !57
  %t1194 = and <16 x i8> %t1193, splat (i8 7), !dbg !57
  %t1195 = lshr <16 x i8> %t1189, %t1194, !dbg !57
  %t1196 = call i32 @nupp.wrap.u32(double 0x3FF0000000000000), !dbg !57
  %t1197 = trunc i32 %t1196 to i8, !dbg !57
  %t1198 = insertelement <16 x i8> poison, i8 %t1197, i64 0, !dbg !57
  %t1199 = shufflevector <16 x i8> %t1198, <16 x i8> poison, <16 x i32> zeroinitializer, !dbg !57
  %t1200 = add <16 x i8> %t1195, %t1199, !dbg !57
  %t1201 = sub <16 x i8> %t1200, splat (i8 1), !dbg !57
  %t1202 = call <16 x i8> @llvm.aarch64.neon.tbl1.v16i8(<16 x i8> %t1188, <16 x i8> %t1201), !dbg !57
  %t1203 = and <16 x i8> %t1187, %t1202, !dbg !57
  store <16 x i8> %t1203, ptr %slot430, !dbg !57
  %t1204 = call i32 @nupp.wrap.u32(double 0x4060000000000000), !dbg !58
  %t1205 = trunc i32 %t1204 to i8, !dbg !58
  %t1206 = insertelement <16 x i8> poison, i8 %t1205, i64 0, !dbg !58
  %t1207 = shufflevector <16 x i8> %t1206, <16 x i8> poison, <16 x i32> zeroinitializer, !dbg !58
  %t1208 = call i32 @nupp.wrap.u32(double 0x0000000000000000), !dbg !58
  %t1209 = trunc i32 %t1208 to i8, !dbg !58
  %t1210 = insertelement <16 x i8> poison, i8 %t1209, i64 0, !dbg !58
  %t1211 = shufflevector <16 x i8> %t1210, <16 x i8> poison, <16 x i32> zeroinitializer, !dbg !58
  %t1212 = load <16 x i8>, ptr %slot365, !dbg !58
  %t1213 = call i32 @nupp.wrap.u32(double 0x406C000000000000), !dbg !58
  %t1214 = trunc i32 %t1213 to i8, !dbg !58
  %t1215 = insertelement <16 x i8> poison, i8 %t1214, i64 0, !dbg !58
  %t1216 = shufflevector <16 x i8> %t1215, <16 x i8> poison, <16 x i32> zeroinitializer, !dbg !58
  %t1217 = icmp uge <16 x i8> %t1212, %t1216, !dbg !58
  %t1218 = load <16 x i8>, ptr %slot369, !dbg !58
  %t1219 = call i32 @nupp.wrap.u32(double 0x406E000000000000), !dbg !58
  %t1220 = trunc i32 %t1219 to i8, !dbg !58
  %t1221 = insertelement <16 x i8> poison, i8 %t1220, i64 0, !dbg !58
  %t1222 = shufflevector <16 x i8> %t1221, <16 x i8> poison, <16 x i32> zeroinitializer, !dbg !58
  %t1223 = icmp uge <16 x i8> %t1218, %t1222, !dbg !58
  %t1224 = or <16 x i1> %t1217, %t1223, !dbg !58
  %t1225 = select <16 x i1> %t1224, <16 x i8> %t1207, <16 x i8> %t1211, !dbg !58
  store <16 x i8> %t1225, ptr %slot453, !dbg !58
  %t1226 = load <16 x i8>, ptr %slot430, !dbg !59
  %t1227 = load <16 x i8>, ptr %slot453, !dbg !59
  %t1228 = xor <16 x i8> %t1226, %t1227, !dbg !59
  %t1229 = call i32 @nupp.wrap.u32(double 0x0000000000000000), !dbg !59
  %t1230 = trunc i32 %t1229 to i8, !dbg !59
  %t1231 = zext i8 %t1230 to i32, !dbg !59
  %t1232 = call i32 @llvm.aarch64.neon.umaxv.i32.v16i8(<16 x i8> %t1228), !dbg !59
  %t1233 = trunc i32 %t1232 to i8, !dbg !59
  %t1234 = zext i8 %t1233 to i32, !dbg !59
  %t1235 = icmp ne i32 %t1234, 0, !dbg !59
  br i1 %t1235, label %if.then.332, label %if.else.333, !dbg !59
if.then.332:
  store i1 true, ptr %slot56, !dbg !60
  br label %if.end.331, !dbg !60
if.else.333:
  %t1236 = load <16 x i8>, ptr %slot168, !dbg !61
  %t1237 = load <16 x i8>, ptr %slot168, !dbg !61
  %t1238 = shufflevector <16 x i8> %t1236, <16 x i8> %t1237, <16 x i32> <i32 15, i32 16, i32 17, i32 18, i32 19, i32 20, i32 21, i32 22, i32 23, i32 24, i32 25, i32 26, i32 27, i32 28, i32 29, i32 30>, !dbg !61
  %t1239 = extractelement <16 x i8> %t1238, i32 0, !dbg !61
  %t1240 = zext i8 %t1239 to i32, !dbg !61
  %t1241 = icmp uge i32 %t1240, 128, !dbg !61
  store i1 %t1241, ptr %slot50, !dbg !61
  br label %if.end.331, !dbg !61
if.end.331:
  br label %if.end.308, !dbg !61
if.else.310:
  store i1 false, ptr %slot50, !dbg !62
  br label %if.end.308, !dbg !62
if.end.308:
  %t1242 = load i1, ptr %slot56, !dbg !63
  %t1243 = xor i1 %t1242, true, !dbg !63
  br i1 %t1243, label %if.then.335, label %if.else.336, !dbg !63
if.then.335:
  store i32 16, ptr %slot70, !dbg !64
  br label %if.end.334, !dbg !64
if.else.336:
  %t1244 = call i64 @llvm.fptosi.sat.i64.f64(double 0x0000000000000000), !dbg !65
  %t1245 = call i64 @llvm.fptoui.sat.i64.f64(double 0x0000000000000000), !dbg !65
  %t1246 = fcmp olt double 0x0000000000000000, 0.0, !dbg !65
  %t1247 = select i1 %t1246, i64 %t1244, i64 %t1245, !dbg !65
  store i64 %t1247, ptr %slot68, !dbg !65
  br label %if.end.334, !dbg !65
if.end.334:
  br label %if.end.271, !dbg !65
if.else.275:
  br label %if.end.271, !dbg !65
if.end.271:
  br label %if.end.268, !dbg !65
if.else.270:
  br label %if.end.268, !dbg !65
if.end.268:
  %t1248 = load i32, ptr %slot70, !dbg !66
  %t1249 = icmp eq i32 %t1248, 0, !dbg !66
  br i1 %t1249, label %and.rhs.338, label %and.end.339, !dbg !66
and.rhs.338:
  %t1250 = load i1, ptr %slot49, !dbg !66
  %t1251 = xor i1 %t1250, true, !dbg !66
  br label %and.end.339, !dbg !66
and.end.339:
  %t1252 = phi i1 [ false, %if.end.268 ], [ %t1251, %and.rhs.338 ], !dbg !66
  br i1 %t1252, label %if.then.340, label %if.else.341, !dbg !66
if.then.340:
  store i1 true, ptr %slot49, !dbg !67
  %t1253 = call i32 @nupp.wrap.u32(double 0x3FF0000000000000), !dbg !68
  store i32 %t1253, ptr %slot482, !dbg !68
  store i1 true, ptr %slot483, !dbg !69
  br label %while.head.342, !dbg !70
while.head.342:
  %t1254 = load i1, ptr %slot483, !dbg !70
  br i1 %t1254, label %and.rhs.345, label %and.end.346, !dbg !70
and.rhs.345:
  %t1255 = load i32, ptr %slot482, !dbg !70
  %t1256 = icmp ule i32 %t1255, 3, !dbg !70
  br label %and.end.346, !dbg !70
and.end.346:
  %t1257 = phi i1 [ false, %while.head.342 ], [ %t1256, %and.rhs.345 ], !dbg !70
  br i1 %t1257, label %and.rhs.347, label %and.end.348, !dbg !70
and.rhs.347:
  %t1258 = load i32, ptr %slot482, !dbg !70
  %t1259 = load i32, ptr %slot33, !dbg !70
  %t1260 = icmp ule i32 %t1258, %t1259, !dbg !70
  br label %and.end.348, !dbg !70
and.end.348:
  %t1261 = phi i1 [ false, %and.end.346 ], [ %t1260, %and.rhs.347 ], !dbg !70
  br i1 %t1261, label %while.body.343, label %while.end.344, !dbg !70
while.body.343:
  %t1262 = load i32, ptr %slot33, !dbg !71
  %t1263 = load i32, ptr %slot482, !dbg !71
  %t1264 = sub i32 %t1262, %t1263, !dbg !71
  %t1265 = zext i32 %t1264 to i64, !dbg !71
  %t1266 = icmp uge i64 %t1265, %t15, !dbg !71
  br i1 %t1266, label %lua.raise.349, label %lua.ok.350, !prof !7, !dbg !71
lua.raise.349:
  %t1267 = getelementptr inbounds ptr, ptr %t1, i64 11, !dbg !71
  %rt.raise.1268 = load ptr, ptr %t1267, !invariant.load !8, !dbg !71
  call void %rt.raise.1268(ptr %L, i64 3) nomerge, !dbg !71
  unreachable, !dbg !71
lua.ok.350:
  %t1269 = getelementptr inbounds i8, ptr %t14, i64 %t1265, !dbg !71
  %t1270 = load i8, ptr %t1269, !dbg !71
  %t1271 = zext i8 %t1270 to i32, !dbg !71
  store i32 %t1271, ptr %slot502, !dbg !71
  %t1272 = load i32, ptr %slot502, !dbg !72
  %t1273 = icmp ult i32 %t1272, 128, !dbg !72
  br i1 %t1273, label %if.then.352, label %if.else.353, !dbg !72
if.then.352:
  store i1 false, ptr %slot483, !dbg !73
  br label %if.end.351, !dbg !73
if.else.353:
  %t1274 = load i32, ptr %slot502, !dbg !73
  %t1275 = icmp uge i32 %t1274, 192, !dbg !73
  br i1 %t1275, label %if.then.354, label %if.else.355, !dbg !73
if.then.354:
  %t1276 = load i32, ptr %slot502, !dbg !74
  %t1277 = icmp ult i32 %t1276, 194, !dbg !74
  br i1 %t1277, label %or.end.358, label %or.rhs.357, !dbg !74
or.rhs.357:
  %t1278 = load i32, ptr %slot502, !dbg !74
  %t1279 = icmp ugt i32 %t1278, 244, !dbg !74
  br label %or.end.358, !dbg !74
or.end.358:
  %t1280 = phi i1 [ true, %if.then.354 ], [ %t1279, %or.rhs.357 ], !dbg !74
  br i1 %t1280, label %if.then.359, label %if.else.360, !dbg !74
if.then.359:
  call void @lua_pushvalue(ptr %L, i32 2), !dbg !75
  %t1281 = call i32 @nupp.wrap.u32(double 0x4000000000000000), !dbg !75
  %t1282 = uitofp i32 %t1281 to double, !dbg !75
  call void @lua_pushnumber(ptr %L, double %t1282), !dbg !75
  %t1283 = load i32, ptr %slot33, !dbg !75
  %t1284 = load i32, ptr %slot482, !dbg !75
  %t1285 = sub i32 %t1283, %t1284, !dbg !75
  %t1286 = add i32 %t1285, 1, !dbg !75
  %t1287 = uitofp i32 %t1286 to double, !dbg !75
  call void @lua_pushnumber(ptr %L, double %t1287), !dbg !75
  ret i32 3, !dbg !75
if.else.360:
  br label %if.end.356, !dbg !75
if.end.356:
  %t1288 = call i32 @nupp.wrap.u32(double 0x4008000000000000), !dbg !76
  store i32 %t1288, ptr %slot520, !dbg !76
  %t1289 = load i32, ptr %slot502, !dbg !77
  %t1290 = icmp ule i32 %t1289, 223, !dbg !77
  br i1 %t1290, label %if.then.362, label %if.else.363, !dbg !77
if.then.362:
  %t1291 = call i32 @nupp.wrap.u32(double 0x3FF0000000000000), !dbg !78
  store i32 %t1291, ptr %slot520, !dbg !78
  br label %if.end.361, !dbg !78
if.else.363:
  %t1292 = load i32, ptr %slot502, !dbg !78
  %t1293 = icmp ule i32 %t1292, 239, !dbg !78
  br i1 %t1293, label %if.then.364, label %if.else.365, !dbg !78
if.then.364:
  %t1294 = call i32 @nupp.wrap.u32(double 0x4000000000000000), !dbg !79
  store i32 %t1294, ptr %slot520, !dbg !79
  br label %if.end.361, !dbg !79
if.else.365:
  br label %if.end.361, !dbg !79
if.end.361:
  %t1295 = load i32, ptr %slot520, !dbg !80
  %t1296 = load i32, ptr %slot482, !dbg !80
  %t1297 = icmp uge i32 %t1295, %t1296, !dbg !80
  br i1 %t1297, label %if.then.367, label %if.else.368, !dbg !80
if.then.367:
  %t1298 = load i32, ptr %slot520, !dbg !81
  %t1299 = load i32, ptr %slot482, !dbg !81
  %t1300 = sub i32 %t1298, %t1299, !dbg !81
  %t1301 = add i32 %t1300, 1, !dbg !81
  store i32 %t1301, ptr %slot43, !dbg !81
  store i1 true, ptr %slot46, !dbg !82
  %t1302 = load i32, ptr %slot33, !dbg !83
  %t1303 = sub i32 %t1302, 1, !dbg !83
  store i32 %t1303, ptr %slot48, !dbg !83
  %t1304 = load i32, ptr %slot482, !dbg !84
  %t1305 = icmp eq i32 %t1304, 1, !dbg !84
  br i1 %t1305, label %if.then.370, label %if.else.371, !dbg !84
if.then.370:
  %t1306 = load i32, ptr %slot502, !dbg !85
  %t1307 = icmp eq i32 %t1306, 224, !dbg !85
  br i1 %t1307, label %if.then.373, label %if.else.374, !dbg !85
if.then.373:
  %t1308 = call i32 @nupp.wrap.u32(double 0x3FF0000000000000), !dbg !86
  store i32 %t1308, ptr %slot45, !dbg !86
  br label %if.end.372, !dbg !86
if.else.374:
  %t1309 = load i32, ptr %slot502, !dbg !86
  %t1310 = icmp eq i32 %t1309, 237, !dbg !86
  br i1 %t1310, label %if.then.375, label %if.else.376, !dbg !86
if.then.375:
  %t1311 = call i32 @nupp.wrap.u32(double 0x4000000000000000), !dbg !87
  store i32 %t1311, ptr %slot45, !dbg !87
  br label %if.end.372, !dbg !87
if.else.376:
  %t1312 = load i32, ptr %slot502, !dbg !87
  %t1313 = icmp eq i32 %t1312, 240, !dbg !87
  br i1 %t1313, label %if.then.377, label %if.else.378, !dbg !87
if.then.377:
  %t1314 = call i32 @nupp.wrap.u32(double 0x4008000000000000), !dbg !88
  store i32 %t1314, ptr %slot45, !dbg !88
  br label %if.end.372, !dbg !88
if.else.378:
  %t1315 = load i32, ptr %slot502, !dbg !88
  %t1316 = icmp eq i32 %t1315, 244, !dbg !88
  br i1 %t1316, label %if.then.379, label %if.else.380, !dbg !88
if.then.379:
  %t1317 = call i32 @nupp.wrap.u32(double 0x4010000000000000), !dbg !89
  store i32 %t1317, ptr %slot45, !dbg !89
  br label %if.end.372, !dbg !89
if.else.380:
  br label %if.end.372, !dbg !89
if.end.372:
  br label %if.end.369, !dbg !89
if.else.371:
  br label %if.end.369, !dbg !89
if.end.369:
  br label %if.end.366, !dbg !89
if.else.368:
  br label %if.end.366, !dbg !89
if.end.366:
  store i1 false, ptr %slot483, !dbg !90
  br label %if.end.351, !dbg !90
if.else.355:
  %t1318 = load i32, ptr %slot482, !dbg !91
  %t1319 = add i32 %t1318, 1, !dbg !91
  store i32 %t1319, ptr %slot482, !dbg !91
  br label %if.end.351, !dbg !91
if.end.351:
  br label %while.head.342, !dbg !91
while.end.344:
  br label %if.end.337, !dbg !91
if.else.341:
  %t1320 = load i32, ptr %slot70, !dbg !91
  %t1321 = icmp eq i32 %t1320, 0, !dbg !91
  br i1 %t1321, label %if.then.381, label %if.else.382, !dbg !91
if.then.381:
  %t1322 = load i32, ptr %slot33, !dbg !92
  %t1323 = load i32, ptr %slot20, !dbg !92
  %t1324 = icmp ult i32 %t1322, %t1323, !dbg !92
  br i1 %t1324, label %if.then.384, label %if.else.385, !dbg !92
if.then.384:
  %t1325 = load i32, ptr %slot33, !dbg !93
  %t1326 = zext i32 %t1325 to i64, !dbg !93
  %t1327 = getelementptr inbounds i8, ptr %t14, i64 %t1326, !dbg !93
  %t1328 = load i8, ptr %t1327, !dbg !93
  %t1329 = zext i8 %t1328 to i32, !dbg !93
  store i32 %t1329, ptr %slot562, !dbg !93
  %t1330 = load i32, ptr %slot562, !dbg !94
  %t1331 = icmp eq i32 %t1330, 34, !dbg !94
  br i1 %t1331, label %or.end.388, label %or.rhs.387, !dbg !94
or.rhs.387:
  %t1332 = load i32, ptr %slot562, !dbg !94
  %t1333 = icmp eq i32 %t1332, 92, !dbg !94
  br label %or.end.388, !dbg !94
or.end.388:
  %t1334 = phi i1 [ true, %if.then.384 ], [ %t1333, %or.rhs.387 ], !dbg !94
  br i1 %t1334, label %or.end.390, label %or.rhs.389, !dbg !94
or.rhs.389:
  %t1335 = load i32, ptr %slot562, !dbg !94
  %t1336 = icmp ult i32 %t1335, 32, !dbg !94
  br label %or.end.390, !dbg !94
or.end.390:
  %t1337 = phi i1 [ true, %or.end.388 ], [ %t1336, %or.rhs.389 ], !dbg !94
  br i1 %t1337, label %or.end.392, label %or.rhs.391, !dbg !94
or.rhs.391:
  %t1338 = load i32, ptr %slot562, !dbg !94
  %t1339 = icmp eq i32 %t1338, 123, !dbg !94
  br label %or.end.392, !dbg !94
or.end.392:
  %t1340 = phi i1 [ true, %or.end.390 ], [ %t1339, %or.rhs.391 ], !dbg !94
  br i1 %t1340, label %or.end.394, label %or.rhs.393, !dbg !94
or.rhs.393:
  %t1341 = load i32, ptr %slot562, !dbg !94
  %t1342 = icmp eq i32 %t1341, 125, !dbg !94
  br label %or.end.394, !dbg !94
or.end.394:
  %t1343 = phi i1 [ true, %or.end.392 ], [ %t1342, %or.rhs.393 ], !dbg !94
  br i1 %t1343, label %or.end.396, label %or.rhs.395, !dbg !94
or.rhs.395:
  %t1344 = load i32, ptr %slot562, !dbg !94
  %t1345 = icmp eq i32 %t1344, 91, !dbg !94
  br label %or.end.396, !dbg !94
or.end.396:
  %t1346 = phi i1 [ true, %or.end.394 ], [ %t1345, %or.rhs.395 ], !dbg !94
  br i1 %t1346, label %or.end.398, label %or.rhs.397, !dbg !94
or.rhs.397:
  %t1347 = load i32, ptr %slot562, !dbg !94
  %t1348 = icmp eq i32 %t1347, 93, !dbg !94
  br label %or.end.398, !dbg !94
or.end.398:
  %t1349 = phi i1 [ true, %or.end.396 ], [ %t1348, %or.rhs.397 ], !dbg !94
  br i1 %t1349, label %or.end.400, label %or.rhs.399, !dbg !94
or.rhs.399:
  %t1350 = load i32, ptr %slot562, !dbg !94
  %t1351 = icmp eq i32 %t1350, 58, !dbg !94
  br label %or.end.400, !dbg !94
or.end.400:
  %t1352 = phi i1 [ true, %or.end.398 ], [ %t1351, %or.rhs.399 ], !dbg !94
  br i1 %t1352, label %or.end.402, label %or.rhs.401, !dbg !94
or.rhs.401:
  %t1353 = load i32, ptr %slot562, !dbg !94
  %t1354 = icmp eq i32 %t1353, 44, !dbg !94
  br label %or.end.402, !dbg !94
or.end.402:
  %t1355 = phi i1 [ true, %or.end.400 ], [ %t1354, %or.rhs.401 ], !dbg !94
  br i1 %t1355, label %or.end.404, label %or.rhs.403, !dbg !94
or.rhs.403:
  %t1356 = load i32, ptr %slot562, !dbg !94
  %t1357 = icmp uge i32 %t1356, 128, !dbg !94
  br label %or.end.404, !dbg !94
or.end.404:
  %t1358 = phi i1 [ true, %or.end.402 ], [ %t1357, %or.rhs.403 ], !dbg !94
  br i1 %t1358, label %if.then.405, label %if.else.406, !dbg !94
if.then.405:
  %t1359 = load i64, ptr %slot55, !dbg !95
  store i64 %t1359, ptr %slot68, !dbg !95
  br label %if.end.386, !dbg !95
if.else.406:
  br label %if.end.386, !dbg !95
if.end.386:
  br label %if.end.383, !dbg !95
if.else.385:
  br label %if.end.383, !dbg !95
if.end.383:
  %t1360 = call i32 @nupp.wrap.u32(double 0x3FF0000000000000), !dbg !96
  store i32 %t1360, ptr %slot70, !dbg !96
  br label %if.end.337, !dbg !96
if.else.382:
  br label %if.end.337, !dbg !96
if.end.337:
  br label %while.head.407, !dbg !97
while.head.407:
  %t1361 = load i64, ptr %slot68, !dbg !97
  %t1362 = call i64 @llvm.fptosi.sat.i64.f64(double 0x0000000000000000), !dbg !97
  %t1363 = call i64 @llvm.fptoui.sat.i64.f64(double 0x0000000000000000), !dbg !97
  %t1364 = fcmp olt double 0x0000000000000000, 0.0, !dbg !97
  %t1365 = select i1 %t1364, i64 %t1362, i64 %t1363, !dbg !97
  %t1366 = icmp ne i64 %t1361, %t1365, !dbg !97
  br i1 %t1366, label %while.body.408, label %while.end.409, !dbg !97
while.body.408:
  %t1367 = load i64, ptr %slot68, !dbg !98
  %t1368 = call i64 @llvm.cttz.i64(i64 %t1367, i1 false), !dbg !98
  %t1369 = trunc i64 %t1368 to i32, !dbg !98
  store i32 %t1369, ptr %slot603, !dbg !98
  %t1370 = load i64, ptr %slot68, !dbg !99
  %t1371 = load i64, ptr %slot68, !dbg !99
  %t1372 = call i64 @llvm.fptosi.sat.i64.f64(double 0x3FF0000000000000), !dbg !99
  %t1373 = call i64 @llvm.fptoui.sat.i64.f64(double 0x3FF0000000000000), !dbg !99
  %t1374 = fcmp olt double 0x3FF0000000000000, 0.0, !dbg !99
  %t1375 = select i1 %t1374, i64 %t1372, i64 %t1373, !dbg !99
  %t1376 = sub i64 %t1371, %t1375, !dbg !99
  %t1377 = and i64 %t1370, %t1376, !dbg !99
  store i64 %t1377, ptr %slot68, !dbg !99
  %t1378 = load i32, ptr %slot33, !dbg !100
  %t1379 = load i32, ptr %slot603, !dbg !100
  %t1380 = add i32 %t1378, %t1379, !dbg !100
  store i32 %t1380, ptr %slot615, !dbg !100
  %t1381 = load i32, ptr %slot615, !dbg !101
  %t1382 = load i32, ptr %slot20, !dbg !101
  %t1383 = icmp ult i32 %t1381, %t1382, !dbg !101
  br i1 %t1383, label %if.then.411, label %if.else.412, !dbg !101
if.then.411:
  %t1384 = load i32, ptr %slot615, !dbg !102
  %t1385 = zext i32 %t1384 to i64, !dbg !102
  %t1386 = getelementptr inbounds i8, ptr %t14, i64 %t1385, !dbg !102
  %t1387 = load i8, ptr %t1386, !dbg !102
  %t1388 = zext i8 %t1387 to i32, !dbg !102
  store i32 %t1388, ptr %slot624, !dbg !102
  %t1389 = load i32, ptr %slot43, !dbg !103
  %t1390 = icmp ne i32 %t1389, 0, !dbg !103
  br i1 %t1390, label %and.rhs.414, label %and.end.415, !dbg !103
and.rhs.414:
  %t1391 = load i1, ptr %slot46, !dbg !103
  %t1392 = xor i1 %t1391, true, !dbg !103
  br i1 %t1392, label %or.end.417, label %or.rhs.416, !dbg !103
or.rhs.416:
  %t1393 = load i32, ptr %slot615, !dbg !103
  %t1394 = load i32, ptr %slot48, !dbg !103
  %t1395 = add i32 %t1394, 1, !dbg !103
  %t1396 = icmp ne i32 %t1393, %t1395, !dbg !103
  br label %or.end.417, !dbg !103
or.end.417:
  %t1397 = phi i1 [ true, %and.rhs.414 ], [ %t1396, %or.rhs.416 ], !dbg !103
  br label %and.end.415, !dbg !103
and.end.415:
  %t1398 = phi i1 [ false, %if.then.411 ], [ %t1397, %or.end.417 ], !dbg !103
  br i1 %t1398, label %if.then.418, label %if.else.419, !dbg !103
if.then.418:
  call void @lua_pushvalue(ptr %L, i32 2), !dbg !104
  %t1399 = call i32 @nupp.wrap.u32(double 0x4000000000000000), !dbg !104
  %t1400 = uitofp i32 %t1399 to double, !dbg !104
  call void @lua_pushnumber(ptr %L, double %t1400), !dbg !104
  %t1401 = load i32, ptr %slot48, !dbg !104
  %t1402 = add i32 %t1401, 2, !dbg !104
  %t1403 = uitofp i32 %t1402 to double, !dbg !104
  call void @lua_pushnumber(ptr %L, double %t1403), !dbg !104
  ret i32 3, !dbg !104
if.else.419:
  br label %if.end.413, !dbg !104
if.end.413:
  %t1404 = load i32, ptr %slot624, !dbg !105
  %t1405 = icmp uge i32 %t1404, 128, !dbg !105
  br i1 %t1405, label %if.then.421, label %if.else.422, !dbg !105
if.then.421:
  %t1406 = load i32, ptr %slot624, !dbg !106
  %t1407 = icmp ule i32 %t1406, 191, !dbg !106
  store i1 %t1407, ptr %slot644, !dbg !106
  %t1408 = load i32, ptr %slot43, !dbg !107
  %t1409 = icmp ne i32 %t1408, 0, !dbg !107
  br i1 %t1409, label %if.then.424, label %if.else.425, !dbg !107
if.then.424:
  %t1410 = load i1, ptr %slot644, !dbg !108
  %t1411 = xor i1 %t1410, true, !dbg !108
  br i1 %t1411, label %if.then.427, label %if.else.428, !dbg !108
if.then.427:
  call void @lua_pushvalue(ptr %L, i32 2), !dbg !109
  %t1412 = call i32 @nupp.wrap.u32(double 0x4000000000000000), !dbg !109
  %t1413 = uitofp i32 %t1412 to double, !dbg !109
  call void @lua_pushnumber(ptr %L, double %t1413), !dbg !109
  %t1414 = load i32, ptr %slot615, !dbg !109
  %t1415 = add i32 %t1414, 1, !dbg !109
  %t1416 = uitofp i32 %t1415 to double, !dbg !109
  call void @lua_pushnumber(ptr %L, double %t1416), !dbg !109
  ret i32 3, !dbg !109
if.else.428:
  br label %if.end.426, !dbg !109
if.end.426:
  %t1417 = load i32, ptr %slot45, !dbg !110
  %t1418 = icmp eq i32 %t1417, 1, !dbg !110
  br i1 %t1418, label %and.rhs.429, label %and.end.430, !dbg !110
and.rhs.429:
  %t1419 = load i32, ptr %slot624, !dbg !110
  %t1420 = icmp ult i32 %t1419, 160, !dbg !110
  br label %and.end.430, !dbg !110
and.end.430:
  %t1421 = phi i1 [ false, %if.end.426 ], [ %t1420, %and.rhs.429 ], !dbg !110
  br i1 %t1421, label %or.end.432, label %or.rhs.431, !dbg !110
or.rhs.431:
  %t1422 = load i32, ptr %slot45, !dbg !110
  %t1423 = icmp eq i32 %t1422, 2, !dbg !110
  br i1 %t1423, label %and.rhs.433, label %and.end.434, !dbg !110
and.rhs.433:
  %t1424 = load i32, ptr %slot624, !dbg !110
  %t1425 = icmp ugt i32 %t1424, 159, !dbg !110
  br label %and.end.434, !dbg !110
and.end.434:
  %t1426 = phi i1 [ false, %or.rhs.431 ], [ %t1425, %and.rhs.433 ], !dbg !110
  br label %or.end.432, !dbg !110
or.end.432:
  %t1427 = phi i1 [ true, %and.end.430 ], [ %t1426, %and.end.434 ], !dbg !110
  br i1 %t1427, label %or.end.436, label %or.rhs.435, !dbg !110
or.rhs.435:
  %t1428 = load i32, ptr %slot45, !dbg !110
  %t1429 = icmp eq i32 %t1428, 3, !dbg !110
  br i1 %t1429, label %and.rhs.437, label %and.end.438, !dbg !110
and.rhs.437:
  %t1430 = load i32, ptr %slot624, !dbg !110
  %t1431 = icmp ult i32 %t1430, 144, !dbg !110
  br label %and.end.438, !dbg !110
and.end.438:
  %t1432 = phi i1 [ false, %or.rhs.435 ], [ %t1431, %and.rhs.437 ], !dbg !110
  br label %or.end.436, !dbg !110
or.end.436:
  %t1433 = phi i1 [ true, %or.end.432 ], [ %t1432, %and.end.438 ], !dbg !110
  br i1 %t1433, label %or.end.440, label %or.rhs.439, !dbg !110
or.rhs.439:
  %t1434 = load i32, ptr %slot45, !dbg !110
  %t1435 = icmp eq i32 %t1434, 4, !dbg !110
  br i1 %t1435, label %and.rhs.441, label %and.end.442, !dbg !110
and.rhs.441:
  %t1436 = load i32, ptr %slot624, !dbg !110
  %t1437 = icmp ugt i32 %t1436, 143, !dbg !110
  br label %and.end.442, !dbg !110
and.end.442:
  %t1438 = phi i1 [ false, %or.rhs.439 ], [ %t1437, %and.rhs.441 ], !dbg !110
  br label %or.end.440, !dbg !110
or.end.440:
  %t1439 = phi i1 [ true, %or.end.436 ], [ %t1438, %and.end.442 ], !dbg !110
  store i1 %t1439, ptr %slot677, !dbg !110
  %t1440 = load i1, ptr %slot677, !dbg !111
  br i1 %t1440, label %if.then.444, label %if.else.445, !dbg !111
if.then.444:
  call void @lua_pushvalue(ptr %L, i32 2), !dbg !112
  %t1441 = call i32 @nupp.wrap.u32(double 0x4000000000000000), !dbg !112
  %t1442 = uitofp i32 %t1441 to double, !dbg !112
  call void @lua_pushnumber(ptr %L, double %t1442), !dbg !112
  %t1443 = load i32, ptr %slot615, !dbg !112
  %t1444 = add i32 %t1443, 1, !dbg !112
  %t1445 = uitofp i32 %t1444 to double, !dbg !112
  call void @lua_pushnumber(ptr %L, double %t1445), !dbg !112
  ret i32 3, !dbg !112
if.else.445:
  br label %if.end.443, !dbg !112
if.end.443:
  %t1446 = load i32, ptr %slot43, !dbg !113
  %t1447 = sub i32 %t1446, 1, !dbg !113
  store i32 %t1447, ptr %slot43, !dbg !113
  %t1448 = call i32 @nupp.wrap.u32(double 0x0000000000000000), !dbg !114
  store i32 %t1448, ptr %slot45, !dbg !114
  br label %if.end.423, !dbg !114
if.else.425:
  %t1449 = load i1, ptr %slot644, !dbg !114
  br i1 %t1449, label %or.end.447, label %or.rhs.446, !dbg !114
or.rhs.446:
  %t1450 = load i32, ptr %slot624, !dbg !114
  %t1451 = icmp ult i32 %t1450, 194, !dbg !114
  br label %or.end.447, !dbg !114
or.end.447:
  %t1452 = phi i1 [ true, %if.else.425 ], [ %t1451, %or.rhs.446 ], !dbg !114
  br i1 %t1452, label %or.end.449, label %or.rhs.448, !dbg !114
or.rhs.448:
  %t1453 = load i32, ptr %slot624, !dbg !114
  %t1454 = icmp ugt i32 %t1453, 244, !dbg !114
  br label %or.end.449, !dbg !114
or.end.449:
  %t1455 = phi i1 [ true, %or.end.447 ], [ %t1454, %or.rhs.448 ], !dbg !114
  br i1 %t1455, label %if.then.450, label %if.else.451, !dbg !114
if.then.450:
  call void @lua_pushvalue(ptr %L, i32 2), !dbg !115
  %t1456 = call i32 @nupp.wrap.u32(double 0x4000000000000000), !dbg !115
  %t1457 = uitofp i32 %t1456 to double, !dbg !115
  call void @lua_pushnumber(ptr %L, double %t1457), !dbg !115
  %t1458 = load i32, ptr %slot615, !dbg !115
  %t1459 = add i32 %t1458, 1, !dbg !115
  %t1460 = uitofp i32 %t1459 to double, !dbg !115
  call void @lua_pushnumber(ptr %L, double %t1460), !dbg !115
  ret i32 3, !dbg !115
if.else.451:
  %t1461 = load i32, ptr %slot624, !dbg !115
  %t1462 = icmp ule i32 %t1461, 223, !dbg !115
  br i1 %t1462, label %if.then.452, label %if.else.453, !dbg !115
if.then.452:
  %t1463 = call i32 @nupp.wrap.u32(double 0x3FF0000000000000), !dbg !116
  store i32 %t1463, ptr %slot43, !dbg !116
  br label %if.end.423, !dbg !116
if.else.453:
  %t1464 = load i32, ptr %slot624, !dbg !116
  %t1465 = icmp ule i32 %t1464, 239, !dbg !116
  br i1 %t1465, label %if.then.454, label %if.else.455, !dbg !116
if.then.454:
  %t1466 = call i32 @nupp.wrap.u32(double 0x4000000000000000), !dbg !117
  store i32 %t1466, ptr %slot43, !dbg !117
  %t1467 = load i32, ptr %slot624, !dbg !118
  %t1468 = icmp eq i32 %t1467, 224, !dbg !118
  br i1 %t1468, label %if.then.457, label %if.else.458, !dbg !118
if.then.457:
  %t1469 = call i32 @nupp.wrap.u32(double 0x3FF0000000000000), !dbg !119
  store i32 %t1469, ptr %slot45, !dbg !119
  br label %if.end.456, !dbg !119
if.else.458:
  %t1470 = load i32, ptr %slot624, !dbg !119
  %t1471 = icmp eq i32 %t1470, 237, !dbg !119
  br i1 %t1471, label %if.then.459, label %if.else.460, !dbg !119
if.then.459:
  %t1472 = call i32 @nupp.wrap.u32(double 0x4000000000000000), !dbg !120
  store i32 %t1472, ptr %slot45, !dbg !120
  br label %if.end.456, !dbg !120
if.else.460:
  br label %if.end.456, !dbg !120
if.end.456:
  br label %if.end.423, !dbg !120
if.else.455:
  %t1473 = call i32 @nupp.wrap.u32(double 0x4008000000000000), !dbg !121
  store i32 %t1473, ptr %slot43, !dbg !121
  %t1474 = load i32, ptr %slot624, !dbg !122
  %t1475 = icmp eq i32 %t1474, 240, !dbg !122
  br i1 %t1475, label %if.then.462, label %if.else.463, !dbg !122
if.then.462:
  %t1476 = call i32 @nupp.wrap.u32(double 0x4008000000000000), !dbg !123
  store i32 %t1476, ptr %slot45, !dbg !123
  br label %if.end.461, !dbg !123
if.else.463:
  %t1477 = load i32, ptr %slot624, !dbg !123
  %t1478 = icmp eq i32 %t1477, 244, !dbg !123
  br i1 %t1478, label %if.then.464, label %if.else.465, !dbg !123
if.then.464:
  %t1479 = call i32 @nupp.wrap.u32(double 0x4010000000000000), !dbg !124
  store i32 %t1479, ptr %slot45, !dbg !124
  br label %if.end.461, !dbg !124
if.else.465:
  br label %if.end.461, !dbg !124
if.end.461:
  br label %if.end.423, !dbg !124
if.end.423:
  store i1 true, ptr %slot46, !dbg !125
  %t1480 = load i32, ptr %slot615, !dbg !126
  store i32 %t1480, ptr %slot48, !dbg !126
  store i1 false, ptr %slot39, !dbg !127
  store i1 false, ptr %slot38, !dbg !128
  br label %if.end.420, !dbg !128
if.else.422:
  %t1481 = load i32, ptr %slot43, !dbg !128
  %t1482 = icmp ne i32 %t1481, 0, !dbg !128
  br i1 %t1482, label %if.then.466, label %if.else.467, !dbg !128
if.then.466:
  call void @lua_pushvalue(ptr %L, i32 2), !dbg !129
  %t1483 = call i32 @nupp.wrap.u32(double 0x4000000000000000), !dbg !129
  %t1484 = uitofp i32 %t1483 to double, !dbg !129
  call void @lua_pushnumber(ptr %L, double %t1484), !dbg !129
  %t1485 = load i32, ptr %slot615, !dbg !129
  %t1486 = add i32 %t1485, 1, !dbg !129
  %t1487 = uitofp i32 %t1486 to double, !dbg !129
  call void @lua_pushnumber(ptr %L, double %t1487), !dbg !129
  ret i32 3, !dbg !129
if.else.467:
  %t1488 = load i32, ptr %slot624, !dbg !129
  %t1489 = icmp eq i32 %t1488, 92, !dbg !129
  br i1 %t1489, label %if.then.468, label %if.else.469, !dbg !129
if.then.468:
  %t1490 = load i1, ptr %slot36, !dbg !130
  %t1491 = xor i1 %t1490, true, !dbg !130
  br i1 %t1491, label %if.then.471, label %if.else.472, !dbg !130
if.then.471:
  call void @lua_pushvalue(ptr %L, i32 2), !dbg !131
  %t1492 = call i32 @nupp.wrap.u32(double 0x4010000000000000), !dbg !131
  %t1493 = uitofp i32 %t1492 to double, !dbg !131
  call void @lua_pushnumber(ptr %L, double %t1493), !dbg !131
  %t1494 = load i32, ptr %slot615, !dbg !131
  %t1495 = add i32 %t1494, 1, !dbg !131
  %t1496 = uitofp i32 %t1495 to double, !dbg !131
  call void @lua_pushnumber(ptr %L, double %t1496), !dbg !131
  ret i32 3, !dbg !131
if.else.472:
  br label %if.end.470, !dbg !131
if.end.470:
  %t1497 = load i1, ptr %slot39, !dbg !132
  br i1 %t1497, label %and.rhs.474, label %and.end.475, !dbg !132
and.rhs.474:
  %t1498 = load i32, ptr %slot615, !dbg !132
  %t1499 = load i32, ptr %slot41, !dbg !132
  %t1500 = add i32 %t1499, 1, !dbg !132
  %t1501 = icmp eq i32 %t1498, %t1500, !dbg !132
  br label %and.end.475, !dbg !132
and.end.475:
  %t1502 = phi i1 [ false, %if.end.470 ], [ %t1501, %and.rhs.474 ], !dbg !132
  br i1 %t1502, label %if.then.476, label %if.else.477, !dbg !132
if.then.476:
  %t1503 = load i1, ptr %slot38, !dbg !133
  %t1504 = xor i1 %t1503, true, !dbg !133
  store i1 %t1504, ptr %slot38, !dbg !133
  br label %if.end.473, !dbg !133
if.else.477:
  store i1 true, ptr %slot38, !dbg !134
  br label %if.end.473, !dbg !134
if.end.473:
  store i1 true, ptr %slot39, !dbg !135
  %t1505 = load i32, ptr %slot615, !dbg !136
  store i32 %t1505, ptr %slot41, !dbg !136
  store i1 true, ptr %slot37, !dbg !137
  br label %if.end.420, !dbg !137
if.else.469:
  %t1506 = load i1, ptr %slot39, !dbg !138
  br i1 %t1506, label %and.rhs.478, label %and.end.479, !dbg !138
and.rhs.478:
  %t1507 = load i32, ptr %slot615, !dbg !138
  %t1508 = load i32, ptr %slot41, !dbg !138
  %t1509 = add i32 %t1508, 1, !dbg !138
  %t1510 = icmp eq i32 %t1507, %t1509, !dbg !138
  br label %and.end.479, !dbg !138
and.end.479:
  %t1511 = phi i1 [ false, %if.else.469 ], [ %t1510, %and.rhs.478 ], !dbg !138
  br i1 %t1511, label %and.rhs.480, label %and.end.481, !dbg !138
and.rhs.480:
  %t1512 = load i1, ptr %slot38, !dbg !138
  br label %and.end.481, !dbg !138
and.end.481:
  %t1513 = phi i1 [ false, %and.end.479 ], [ %t1512, %and.rhs.480 ], !dbg !138
  store i1 %t1513, ptr %slot752, !dbg !138
  %t1514 = load i32, ptr %slot624, !dbg !139
  %t1515 = icmp eq i32 %t1514, 34, !dbg !139
  br i1 %t1515, label %and.rhs.483, label %and.end.484, !dbg !139
and.rhs.483:
  %t1516 = load i1, ptr %slot752, !dbg !139
  %t1517 = xor i1 %t1516, true, !dbg !139
  br label %and.end.484, !dbg !139
and.end.484:
  %t1518 = phi i1 [ false, %and.end.481 ], [ %t1517, %and.rhs.483 ], !dbg !139
  br i1 %t1518, label %if.then.485, label %if.else.486, !dbg !139
if.then.485:
  %t1519 = load i1, ptr %slot36, !dbg !140
  br i1 %t1519, label %if.then.488, label %if.else.489, !dbg !140
if.then.488:
  %t1520 = load i32, ptr %slot615, !dbg !141
  store i32 %t1520, ptr %slot760, !dbg !141
  %t1521 = load i1, ptr %slot37, !dbg !142
  br i1 %t1521, label %if.then.491, label %if.else.492, !dbg !142
if.then.491:
  %t1522 = load i32, ptr %slot615, !dbg !143
  %t1523 = or i32 %t1522, 2147483648, !dbg !143
  store i32 %t1523, ptr %slot760, !dbg !143
  br label %if.end.490, !dbg !143
if.else.492:
  br label %if.end.490, !dbg !143
if.end.490:
  %t1524 = load i32, ptr %slot35, !dbg !144
  %t1525 = load i32, ptr %slot760, !dbg !144
  %t1526 = getelementptr inbounds { ptr, i32, i32, i32, i32, [32 x i32] }, ptr %slot27, i32 0, i32 2, !dbg !144
  %t1527 = load i32, ptr %t1526, !dbg !144
  %t1528 = getelementptr inbounds { ptr, i32, i32, i32, i32, [32 x i32] }, ptr %slot27, i32 0, i32 1, !dbg !144
  %t1529 = load i32, ptr %t1528, !dbg !144
  %t1530 = icmp ugt i32 %t1524, %t1527, !dbg !144
  %t1531 = icmp uge i32 %t1524, %t1529, !dbg !144
  %t1532 = or i1 %t1530, %t1531, !dbg !144
  br i1 %t1532, label %lua.raise.493, label %lua.ok.494, !prof !7, !dbg !144
lua.raise.493:
  %t1533 = getelementptr inbounds ptr, ptr %t1, i64 11, !dbg !144
  %rt.raise.1534 = load ptr, ptr %t1533, !invariant.load !8, !dbg !144
  call void %rt.raise.1534(ptr %L, i64 8) nomerge, !dbg !144
  unreachable, !dbg !144
lua.ok.494:
  %t1535 = icmp eq i32 %t1524, %t1527, !dbg !144
  %t1536 = add i32 %t1527, 1, !dbg !144
  %t1537 = select i1 %t1535, i32 %t1536, i32 %t1527, !dbg !144
  store i32 %t1537, ptr %t1526, !dbg !144
  %t1538 = getelementptr inbounds { ptr, i32, i32, i32, i32, [32 x i32] }, ptr %slot27, i32 0, i32 0, !dbg !144
  %t1539 = load ptr, ptr %t1538, !dbg !144
  %t1540 = zext i32 %t1524 to i64, !dbg !144
  %t1541 = getelementptr inbounds i32, ptr %t1539, i64 %t1540, !dbg !144
  store i32 %t1525, ptr %t1541, !dbg !144
  store i1 false, ptr %slot36, !dbg !145
  br label %if.end.487, !dbg !145
if.else.489:
  %t1542 = load i32, ptr %slot35, !dbg !146
  %t1543 = load i32, ptr %slot615, !dbg !146
  %t1544 = getelementptr inbounds { ptr, i32, i32, i32, i32, [32 x i32] }, ptr %slot27, i32 0, i32 2, !dbg !146
  %t1545 = load i32, ptr %t1544, !dbg !146
  %t1546 = getelementptr inbounds { ptr, i32, i32, i32, i32, [32 x i32] }, ptr %slot27, i32 0, i32 1, !dbg !146
  %t1547 = load i32, ptr %t1546, !dbg !146
  %t1548 = icmp ugt i32 %t1542, %t1545, !dbg !146
  %t1549 = icmp uge i32 %t1542, %t1547, !dbg !146
  %t1550 = or i1 %t1548, %t1549, !dbg !146
  br i1 %t1550, label %lua.raise.495, label %lua.ok.496, !prof !7, !dbg !146
lua.raise.495:
  %t1551 = getelementptr inbounds ptr, ptr %t1, i64 11, !dbg !146
  %rt.raise.1552 = load ptr, ptr %t1551, !invariant.load !8, !dbg !146
  call void %rt.raise.1552(ptr %L, i64 8) nomerge, !dbg !146
  unreachable, !dbg !146
lua.ok.496:
  %t1553 = icmp eq i32 %t1542, %t1545, !dbg !146
  %t1554 = add i32 %t1545, 1, !dbg !146
  %t1555 = select i1 %t1553, i32 %t1554, i32 %t1545, !dbg !146
  store i32 %t1555, ptr %t1544, !dbg !146
  %t1556 = getelementptr inbounds { ptr, i32, i32, i32, i32, [32 x i32] }, ptr %slot27, i32 0, i32 0, !dbg !146
  %t1557 = load ptr, ptr %t1556, !dbg !146
  %t1558 = zext i32 %t1542 to i64, !dbg !146
  %t1559 = getelementptr inbounds i32, ptr %t1557, i64 %t1558, !dbg !146
  store i32 %t1543, ptr %t1559, !dbg !146
  store i1 true, ptr %slot36, !dbg !147
  store i1 false, ptr %slot37, !dbg !148
  br label %if.end.487, !dbg !148
if.end.487:
  %t1560 = load i32, ptr %slot35, !dbg !149
  %t1561 = add i32 %t1560, 1, !dbg !149
  store i32 %t1561, ptr %slot35, !dbg !149
  br label %if.end.482, !dbg !149
if.else.486:
  %t1562 = load i32, ptr %slot624, !dbg !149
  %t1563 = icmp ult i32 %t1562, 32, !dbg !149
  br i1 %t1563, label %if.then.497, label %if.else.498, !dbg !149
if.then.497:
  %t1564 = load i32, ptr %slot624, !dbg !150
  %t1565 = icmp eq i32 %t1564, 9, !dbg !150
  br i1 %t1565, label %or.end.500, label %or.rhs.499, !dbg !150
or.rhs.499:
  %t1566 = load i32, ptr %slot624, !dbg !150
  %t1567 = icmp eq i32 %t1566, 10, !dbg !150
  br label %or.end.500, !dbg !150
or.end.500:
  %t1568 = phi i1 [ true, %if.then.497 ], [ %t1567, %or.rhs.499 ], !dbg !150
  br i1 %t1568, label %or.end.502, label %or.rhs.501, !dbg !150
or.rhs.501:
  %t1569 = load i32, ptr %slot624, !dbg !150
  %t1570 = icmp eq i32 %t1569, 13, !dbg !150
  br label %or.end.502, !dbg !150
or.end.502:
  %t1571 = phi i1 [ true, %or.end.500 ], [ %t1570, %or.rhs.501 ], !dbg !150
  store i1 %t1571, ptr %slot812, !dbg !150
  %t1572 = load i1, ptr %slot36, !dbg !151
  br i1 %t1572, label %or.end.505, label %or.rhs.504, !dbg !151
or.rhs.504:
  %t1573 = load i1, ptr %slot812, !dbg !151
  %t1574 = xor i1 %t1573, true, !dbg !151
  br label %or.end.505, !dbg !151
or.end.505:
  %t1575 = phi i1 [ true, %or.end.502 ], [ %t1574, %or.rhs.504 ], !dbg !151
  br i1 %t1575, label %if.then.506, label %if.else.507, !dbg !151
if.then.506:
  call void @lua_pushvalue(ptr %L, i32 2), !dbg !152
  %t1576 = call i32 @nupp.wrap.u32(double 0x4008000000000000), !dbg !152
  %t1577 = uitofp i32 %t1576 to double, !dbg !152
  call void @lua_pushnumber(ptr %L, double %t1577), !dbg !152
  %t1578 = load i32, ptr %slot615, !dbg !152
  %t1579 = add i32 %t1578, 1, !dbg !152
  %t1580 = uitofp i32 %t1579 to double, !dbg !152
  call void @lua_pushnumber(ptr %L, double %t1580), !dbg !152
  ret i32 3, !dbg !152
if.else.507:
  br label %if.end.503, !dbg !152
if.end.503:
  br label %if.end.482, !dbg !152
if.else.498:
  %t1581 = load i1, ptr %slot36, !dbg !152
  %t1582 = xor i1 %t1581, true, !dbg !152
  br i1 %t1582, label %if.then.508, label %if.else.509, !dbg !152
if.then.508:
  %t1583 = load i32, ptr %slot35, !dbg !153
  %t1584 = load i32, ptr %slot615, !dbg !153
  %t1585 = getelementptr inbounds { ptr, i32, i32, i32, i32, [32 x i32] }, ptr %slot27, i32 0, i32 2, !dbg !153
  %t1586 = load i32, ptr %t1585, !dbg !153
  %t1587 = getelementptr inbounds { ptr, i32, i32, i32, i32, [32 x i32] }, ptr %slot27, i32 0, i32 1, !dbg !153
  %t1588 = load i32, ptr %t1587, !dbg !153
  %t1589 = icmp ugt i32 %t1583, %t1586, !dbg !153
  %t1590 = icmp uge i32 %t1583, %t1588, !dbg !153
  %t1591 = or i1 %t1589, %t1590, !dbg !153
  br i1 %t1591, label %lua.raise.510, label %lua.ok.511, !prof !7, !dbg !153
lua.raise.510:
  %t1592 = getelementptr inbounds ptr, ptr %t1, i64 11, !dbg !153
  %rt.raise.1593 = load ptr, ptr %t1592, !invariant.load !8, !dbg !153
  call void %rt.raise.1593(ptr %L, i64 8) nomerge, !dbg !153
  unreachable, !dbg !153
lua.ok.511:
  %t1594 = icmp eq i32 %t1583, %t1586, !dbg !153
  %t1595 = add i32 %t1586, 1, !dbg !153
  %t1596 = select i1 %t1594, i32 %t1595, i32 %t1586, !dbg !153
  store i32 %t1596, ptr %t1585, !dbg !153
  %t1597 = getelementptr inbounds { ptr, i32, i32, i32, i32, [32 x i32] }, ptr %slot27, i32 0, i32 0, !dbg !153
  %t1598 = load ptr, ptr %t1597, !dbg !153
  %t1599 = zext i32 %t1583 to i64, !dbg !153
  %t1600 = getelementptr inbounds i32, ptr %t1598, i64 %t1599, !dbg !153
  store i32 %t1584, ptr %t1600, !dbg !153
  %t1601 = load i32, ptr %slot35, !dbg !154
  %t1602 = add i32 %t1601, 1, !dbg !154
  store i32 %t1602, ptr %slot35, !dbg !154
  br label %if.end.482, !dbg !154
if.else.509:
  br label %if.end.482, !dbg !154
if.end.482:
  store i1 false, ptr %slot39, !dbg !155
  store i1 false, ptr %slot38, !dbg !156
  br label %if.end.420, !dbg !156
if.end.420:
  br label %if.end.410, !dbg !156
if.else.412:
  br label %if.end.410, !dbg !156
if.end.410:
  br label %while.head.407, !dbg !156
while.end.409:
  %t1603 = load i32, ptr %slot33, !dbg !157
  %t1604 = load i32, ptr %slot70, !dbg !157
  %t1605 = add i32 %t1603, %t1604, !dbg !157
  store i32 %t1605, ptr %slot33, !dbg !157
  br label %while.head.263, !dbg !157
while.end.265:
  br label %cursors.done.13, !dbg !157
cursors.done.13:
  %t1606 = load i32, ptr %slot43, !dbg !158
  %t1607 = icmp ne i32 %t1606, 0, !dbg !158
  br i1 %t1607, label %if.then.513, label %if.else.514, !dbg !158
if.then.513:
  call void @lua_pushvalue(ptr %L, i32 2), !dbg !159
  %t1608 = call i32 @nupp.wrap.u32(double 0x4000000000000000), !dbg !159
  %t1609 = uitofp i32 %t1608 to double, !dbg !159
  call void @lua_pushnumber(ptr %L, double %t1609), !dbg !159
  %t1610 = load i32, ptr %slot48, !dbg !159
  %t1611 = add i32 %t1610, 2, !dbg !159
  %t1612 = uitofp i32 %t1611 to double, !dbg !159
  call void @lua_pushnumber(ptr %L, double %t1612), !dbg !159
  ret i32 3, !dbg !159
if.else.514:
  br label %if.end.512, !dbg !159
if.end.512:
  %t1613 = call i32 @nupp.wrap.u32(double 0x4090000000000000), !dbg !160
  store i32 %t1613, ptr %slot1614, !dbg !160
  %t1615 = load i32, ptr %slot20, !dbg !161
  %t1616 = icmp ule i32 %t1615, 32, !dbg !161
  br i1 %t1616, label %if.then.516, label %if.else.517, !dbg !161
if.then.516:
  %t1617 = call i32 @nupp.wrap.u32(double 0x4030000000000000), !dbg !162
  store i32 %t1617, ptr %slot1614, !dbg !162
  br label %if.end.515, !dbg !162
if.else.517:
  br label %if.end.515, !dbg !162
if.end.515:
  %t1619 = load i32, ptr %slot1614, !dbg !163
  %t1620 = zext i32 %t1619 to i64, !dbg !163
  %t1621 = load i32, ptr %slot20, !dbg !163
  %t1622 = zext i32 %t1621 to i64, !dbg !163
  %t1623 = sext i32 2 to i64, !dbg !163
  %t1624 = sext i32 3 to i64, !dbg !163
  %t1625 = sext i32 4 to i64, !dbg !163
  %t1626 = getelementptr inbounds ptr, ptr %t1, i64 47, !dbg !163
  %rt.builder_init.1627 = load ptr, ptr %t1626, !invariant.load !8, !dbg !163
  call void %rt.builder_init.1627(ptr %L, ptr %slot1618, i64 %t1623, i64 %t1624, i64 %t1625, i64 %t1620, i64 %t1622, i64 0, i64 0, i64 0, i64 1), !dbg !163
  %t1628 = call i32 @nupp.wrap.u32(double 0x0000000000000000), !dbg !164
  store i32 %t1628, ptr %slot1629, !dbg !164
  %t1630 = getelementptr inbounds { ptr, i32, i32, i32, i32, [32 x i32] }, ptr %slot27, i32 0, i32 2, !dbg !165
  %t1631 = load i32, ptr %t1630, !dbg !165
  store i32 %t1631, ptr %slot35, !dbg !165
  %t1632 = call i32 @nupp.wrap.u32(double 0x0000000000000000), !dbg !166
  store i32 %t1632, ptr %slot1633, !dbg !166
  store i1 true, ptr %slot1634, !dbg !167
  store i1 false, ptr %slot1635, !dbg !168
  %t1636 = call i32 @nupp.wrap.u32(double 0x0000000000000000), !dbg !169
  store i32 %t1636, ptr %slot1637, !dbg !169
  br label %while.head.518, !dbg !170
while.head.518:
  %t1638 = load i1, ptr %slot1635, !dbg !170
  %t1639 = xor i1 %t1638, true, !dbg !170
  br i1 %t1639, label %while.body.519, label %while.end.520, !dbg !170
while.body.519:
  store i1 true, ptr %slot1640, !dbg !171
  %t1641 = call i32 @nupp.wrap.u32(double 0x0000000000000000), !dbg !172
  store i32 %t1641, ptr %slot1637, !dbg !172
  br label %while.head.521, !dbg !173
while.head.521:
  %t1642 = load i1, ptr %slot1640, !dbg !173
  br i1 %t1642, label %and.rhs.524, label %and.end.525, !dbg !173
and.rhs.524:
  %t1643 = load i32, ptr %slot1629, !dbg !173
  %t1644 = load i32, ptr %slot20, !dbg !173
  %t1645 = icmp ult i32 %t1643, %t1644, !dbg !173
  br label %and.end.525, !dbg !173
and.end.525:
  %t1646 = phi i1 [ false, %while.head.521 ], [ %t1645, %and.rhs.524 ], !dbg !173
  br i1 %t1646, label %while.body.522, label %while.end.523, !dbg !173
while.body.522:
  %t1647 = load i32, ptr %slot1629, !dbg !174
  %t1648 = zext i32 %t1647 to i64, !dbg !174
  %t1649 = getelementptr inbounds i8, ptr %t14, i64 %t1648, !dbg !174
  %t1650 = load i8, ptr %t1649, !dbg !174
  %t1651 = zext i8 %t1650 to i32, !dbg !174
  store i32 %t1651, ptr %slot1637, !dbg !174
  %t1652 = load i32, ptr %slot1637, !dbg !175
  %t1653 = icmp eq i32 %t1652, 32, !dbg !175
  br i1 %t1653, label %or.end.528, label %or.rhs.527, !dbg !175
or.rhs.527:
  %t1654 = load i32, ptr %slot1637, !dbg !175
  %t1655 = icmp eq i32 %t1654, 9, !dbg !175
  br label %or.end.528, !dbg !175
or.end.528:
  %t1656 = phi i1 [ true, %while.body.522 ], [ %t1655, %or.rhs.527 ], !dbg !175
  br i1 %t1656, label %or.end.530, label %or.rhs.529, !dbg !175
or.rhs.529:
  %t1657 = load i32, ptr %slot1637, !dbg !175
  %t1658 = icmp eq i32 %t1657, 10, !dbg !175
  br label %or.end.530, !dbg !175
or.end.530:
  %t1659 = phi i1 [ true, %or.end.528 ], [ %t1658, %or.rhs.529 ], !dbg !175
  br i1 %t1659, label %or.end.532, label %or.rhs.531, !dbg !175
or.rhs.531:
  %t1660 = load i32, ptr %slot1637, !dbg !175
  %t1661 = icmp eq i32 %t1660, 13, !dbg !175
  br label %or.end.532, !dbg !175
or.end.532:
  %t1662 = phi i1 [ true, %or.end.530 ], [ %t1661, %or.rhs.531 ], !dbg !175
  br i1 %t1662, label %if.then.533, label %if.else.534, !dbg !175
if.then.533:
  %t1663 = load i32, ptr %slot1629, !dbg !176
  %t1664 = add i32 %t1663, 1, !dbg !176
  store i32 %t1664, ptr %slot1629, !dbg !176
  br label %if.end.526, !dbg !176
if.else.534:
  store i1 false, ptr %slot1640, !dbg !177
  br label %if.end.526, !dbg !177
if.end.526:
  br label %while.head.521, !dbg !177
while.end.523:
  %t1665 = load i1, ptr %slot1634, !dbg !178
  br i1 %t1665, label %if.then.536, label %if.else.537, !dbg !178
if.then.536:
  %t1666 = load i32, ptr %slot1629, !dbg !179
  %t1667 = load i32, ptr %slot20, !dbg !179
  %t1668 = icmp uge i32 %t1666, %t1667, !dbg !179
  br i1 %t1668, label %if.then.539, label %if.else.540, !dbg !179
if.then.539:
  call void @lua_pushvalue(ptr %L, i32 2), !dbg !180
  %t1669 = call i32 @nupp.wrap.u32(double 0x3FF0000000000000), !dbg !180
  %t1670 = uitofp i32 %t1669 to double, !dbg !180
  call void @lua_pushnumber(ptr %L, double %t1670), !dbg !180
  %t1671 = load i32, ptr %slot1629, !dbg !180
  %t1672 = add i32 %t1671, 1, !dbg !180
  %t1673 = uitofp i32 %t1672 to double, !dbg !180
  call void @lua_pushnumber(ptr %L, double %t1673), !dbg !180
  ret i32 3, !dbg !180
if.else.540:
  br label %if.end.538, !dbg !180
if.end.538:
  %t1674 = call i32 @nupp.wrap.u32(double 0x0000000000000000), !dbg !181
  store i32 %t1674, ptr %slot1675, !dbg !181
  %t1676 = load i32, ptr %slot1629, !dbg !182
  store i32 %t1676, ptr %slot1677, !dbg !182
  %t1678 = call i32 @nupp.wrap.u32(double 0x0000000000000000), !dbg !183
  store i32 %t1678, ptr %slot1679, !dbg !183
  %t1680 = call i32 @nupp.wrap.u32(double 0x0000000000000000), !dbg !184
  store i32 %t1680, ptr %slot1681, !dbg !184
  %t1682 = call i32 @nupp.wrap.u32(double 0x0000000000000000), !dbg !185
  store i32 %t1682, ptr %slot1683, !dbg !185
  %t1684 = load i32, ptr %slot1637, !dbg !186
  store i32 %t1684, ptr %slot1685, !dbg !186
  %t1686 = load i32, ptr %slot1685, !dbg !187
  %t1687 = icmp eq i32 %t1686, 34, !dbg !187
  br i1 %t1687, label %if.then.542, label %if.else.543, !dbg !187
if.then.542:
  %t1688 = call i32 @nupp.wrap.u32(double 0x4010000000000000), !dbg !188
  store i32 %t1688, ptr %slot1675, !dbg !188
  %t1689 = load i32, ptr %slot1633, !dbg !189
  %t1690 = load i32, ptr %slot35, !dbg !189
  %t1691 = icmp ult i32 %t1689, %t1690, !dbg !189
  br i1 %t1691, label %if.then.545, label %if.else.546, !dbg !189
if.then.545:
  %t1692 = load i32, ptr %slot1633, !dbg !190
  %t1693 = getelementptr inbounds { ptr, i32, i32, i32, i32, [32 x i32] }, ptr %slot27, i32 0, i32 0, !dbg !190
  %t1694 = load ptr, ptr %t1693, !dbg !190
  %t1695 = zext i32 %t1692 to i64, !dbg !190
  %t1696 = getelementptr inbounds i32, ptr %t1694, i64 %t1695, !dbg !190
  %t1697 = load i32, ptr %t1696, !dbg !190
  store i32 %t1697, ptr %slot1698, !dbg !190
  %t1699 = load i32, ptr %slot1698, !dbg !191
  %t1700 = load i32, ptr %slot1629, !dbg !191
  %t1701 = icmp ne i32 %t1699, %t1700, !dbg !191
  br i1 %t1701, label %if.then.548, label %if.else.549, !dbg !191
if.then.548:
  call void @lua_pushvalue(ptr %L, i32 2), !dbg !192
  %t1702 = call i32 @nupp.wrap.u32(double 0x4014000000000000), !dbg !192
  %t1703 = uitofp i32 %t1702 to double, !dbg !192
  call void @lua_pushnumber(ptr %L, double %t1703), !dbg !192
  %t1704 = load i32, ptr %slot1629, !dbg !192
  %t1705 = add i32 %t1704, 1, !dbg !192
  %t1706 = uitofp i32 %t1705 to double, !dbg !192
  call void @lua_pushnumber(ptr %L, double %t1706), !dbg !192
  ret i32 3, !dbg !192
if.else.549:
  br label %if.end.547, !dbg !192
if.end.547:
  %t1707 = load i32, ptr %slot1633, !dbg !193
  %t1708 = add i32 %t1707, 1, !dbg !193
  store i32 %t1708, ptr %slot1633, !dbg !193
  br label %if.end.544, !dbg !193
if.else.546:
  call void @lua_pushvalue(ptr %L, i32 2), !dbg !194
  %t1709 = call i32 @nupp.wrap.u32(double 0x4014000000000000), !dbg !194
  %t1710 = uitofp i32 %t1709 to double, !dbg !194
  call void @lua_pushnumber(ptr %L, double %t1710), !dbg !194
  %t1711 = load i32, ptr %slot1629, !dbg !194
  %t1712 = add i32 %t1711, 1, !dbg !194
  %t1713 = uitofp i32 %t1712 to double, !dbg !194
  call void @lua_pushnumber(ptr %L, double %t1713), !dbg !194
  ret i32 3, !dbg !194
if.end.544:
  %t1714 = load i32, ptr %slot1633, !dbg !195
  %t1715 = load i32, ptr %slot35, !dbg !195
  %t1716 = icmp ult i32 %t1714, %t1715, !dbg !195
  br i1 %t1716, label %if.then.551, label %if.else.552, !dbg !195
if.then.551:
  %t1717 = load i32, ptr %slot1633, !dbg !196
  %t1718 = getelementptr inbounds { ptr, i32, i32, i32, i32, [32 x i32] }, ptr %slot27, i32 0, i32 0, !dbg !196
  %t1719 = load ptr, ptr %t1718, !dbg !196
  %t1720 = zext i32 %t1717 to i64, !dbg !196
  %t1721 = getelementptr inbounds i32, ptr %t1719, i64 %t1720, !dbg !196
  %t1722 = load i32, ptr %t1721, !dbg !196
  store i32 %t1722, ptr %slot1723, !dbg !196
  %t1724 = load i32, ptr %slot1723, !dbg !197
  %t1725 = and i32 %t1724, 2147483647, !dbg !197
  store i32 %t1725, ptr %slot1726, !dbg !197
  %t1727 = load i32, ptr %slot1723, !dbg !198
  %t1728 = and i32 %t1727, 2147483648, !dbg !198
  %t1729 = icmp ne i32 %t1728, 0, !dbg !198
  br i1 %t1729, label %if.then.554, label %if.else.555, !dbg !198
if.then.554:
  %t1730 = call i32 @nupp.wrap.u32(double 0x3FF0000000000000), !dbg !199
  store i32 %t1730, ptr %slot1681, !dbg !199
  br label %if.end.553, !dbg !199
if.else.555:
  br label %if.end.553, !dbg !199
if.end.553:
  %t1731 = load i32, ptr %slot1629, !dbg !200
  %t1732 = add i32 %t1731, 1, !dbg !200
  store i32 %t1732, ptr %slot1677, !dbg !200
  %t1733 = load i32, ptr %slot1726, !dbg !201
  %t1734 = load i32, ptr %slot1677, !dbg !201
  %t1735 = sub i32 %t1733, %t1734, !dbg !201
  store i32 %t1735, ptr %slot1679, !dbg !201
  %t1736 = load i32, ptr %slot1726, !dbg !202
  %t1737 = add i32 %t1736, 1, !dbg !202
  store i32 %t1737, ptr %slot1629, !dbg !202
  %t1738 = load i32, ptr %slot1633, !dbg !203
  %t1739 = add i32 %t1738, 1, !dbg !203
  store i32 %t1739, ptr %slot1633, !dbg !203
  br label %if.end.550, !dbg !203
if.else.552:
  call void @lua_pushvalue(ptr %L, i32 2), !dbg !204
  %t1740 = call i32 @nupp.wrap.u32(double 0x3FF0000000000000), !dbg !204
  %t1741 = uitofp i32 %t1740 to double, !dbg !204
  call void @lua_pushnumber(ptr %L, double %t1741), !dbg !204
  %t1742 = load i32, ptr %slot1629, !dbg !204
  %t1743 = add i32 %t1742, 1, !dbg !204
  %t1744 = uitofp i32 %t1743 to double, !dbg !204
  call void @lua_pushnumber(ptr %L, double %t1744), !dbg !204
  ret i32 3, !dbg !204
if.end.550:
  br label %if.end.541, !dbg !204
if.else.543:
  %t1745 = load i32, ptr %slot1685, !dbg !204
  %t1746 = icmp eq i32 %t1745, 91, !dbg !204
  br i1 %t1746, label %or.end.557, label %or.rhs.556, !dbg !204
or.rhs.556:
  %t1747 = load i32, ptr %slot1685, !dbg !204
  %t1748 = icmp eq i32 %t1747, 123, !dbg !204
  br label %or.end.557, !dbg !204
or.end.557:
  %t1749 = phi i1 [ true, %if.else.543 ], [ %t1748, %or.rhs.556 ], !dbg !204
  br i1 %t1749, label %if.then.558, label %if.else.559, !dbg !204
if.then.558:
  %t1750 = getelementptr inbounds { [10 x i32], i32, i32, i32, i32, i32, i32, ptr, [16 x { i32, i32, i32, i32, i32, i32, i32, i32, i64, i32, i32, i32, i32 }] }, ptr %slot1618, i32 0, i32 1, !dbg !205
  %t1751 = load i32, ptr %t1750, !dbg !205
  %t1752 = load i32, ptr %slot1614, !dbg !205
  %t1753 = icmp uge i32 %t1751, %t1752, !dbg !205
  br i1 %t1753, label %if.then.561, label %if.else.562, !dbg !205
if.then.561:
  call void @lua_pushvalue(ptr %L, i32 2), !dbg !206
  %t1754 = call i32 @nupp.wrap.u32(double 0x3FF0000000000000), !dbg !206
  %t1755 = uitofp i32 %t1754 to double, !dbg !206
  call void @lua_pushnumber(ptr %L, double %t1755), !dbg !206
  %t1756 = load i32, ptr %slot1629, !dbg !206
  %t1757 = add i32 %t1756, 1, !dbg !206
  %t1758 = uitofp i32 %t1757 to double, !dbg !206
  call void @lua_pushnumber(ptr %L, double %t1758), !dbg !206
  ret i32 3, !dbg !206
if.else.562:
  br label %if.end.560, !dbg !206
if.end.560:
  %t1759 = load i32, ptr %slot1685, !dbg !207
  %t1760 = icmp eq i32 %t1759, 91, !dbg !207
  br i1 %t1760, label %if.then.564, label %if.else.565, !dbg !207
if.then.564:
  %t1761 = call i32 @nupp.wrap.u32(double 0x4014000000000000), !dbg !208
  store i32 %t1761, ptr %slot1675, !dbg !208
  br label %if.end.563, !dbg !208
if.else.565:
  %t1762 = call i32 @nupp.wrap.u32(double 0x4018000000000000), !dbg !209
  store i32 %t1762, ptr %slot1675, !dbg !209
  br label %if.end.563, !dbg !209
if.end.563:
  %t1763 = load i32, ptr %slot1629, !dbg !210
  %t1764 = add i32 %t1763, 1, !dbg !210
  store i32 %t1764, ptr %slot1629, !dbg !210
  %t1765 = load i32, ptr %slot1633, !dbg !211
  %t1766 = load i32, ptr %slot35, !dbg !211
  %t1767 = icmp ult i32 %t1765, %t1766, !dbg !211
  br i1 %t1767, label %if.then.567, label %if.else.568, !dbg !211
if.then.567:
  %t1768 = load i32, ptr %slot1685, !dbg !212
  %t1769 = icmp eq i32 %t1768, 123, !dbg !212
  br i1 %t1769, label %if.then.570, label %if.else.571, !dbg !212
if.then.570:
  %t1770 = call i32 @nupp.wrap.u32(double 0x4010000000000000), !dbg !213
  store i32 %t1770, ptr %slot1683, !dbg !213
  br label %if.end.569, !dbg !213
if.else.571:
  %t1771 = getelementptr inbounds { [10 x i32], i32, i32, i32, i32, i32, i32, ptr, [16 x { i32, i32, i32, i32, i32, i32, i32, i32, i64, i32, i32, i32, i32 }] }, ptr %slot1618, i32 0, i32 1, !dbg !213
  %t1772 = load i32, ptr %t1771, !dbg !213
  %t1773 = icmp eq i32 %t1772, 0, !dbg !213
  br i1 %t1773, label %if.then.572, label %if.else.573, !dbg !213
if.then.572:
  %t1774 = load i32, ptr %slot20, !dbg !214
  %t1775 = and i32 5, 31, !dbg !214
  %t1776 = lshr i32 %t1774, %t1775, !dbg !214
  store i32 %t1776, ptr %slot1683, !dbg !214
  %t1777 = load i32, ptr %slot1683, !dbg !215
  %t1778 = icmp ugt i32 %t1777, 262144, !dbg !215
  br i1 %t1778, label %if.then.575, label %if.else.576, !dbg !215
if.then.575:
  %t1779 = call i32 @nupp.wrap.u32(double 0x4110000000000000), !dbg !216
  store i32 %t1779, ptr %slot1683, !dbg !216
  br label %if.end.574, !dbg !216
if.else.576:
  br label %if.end.574, !dbg !216
if.end.574:
  br label %if.end.569, !dbg !216
if.else.573:
  %t1780 = call i32 @nupp.wrap.u32(double 0x4010000000000000), !dbg !217
  store i32 %t1780, ptr %slot1683, !dbg !217
  br label %if.end.569, !dbg !217
if.end.569:
  %t1781 = load i32, ptr %slot1633, !dbg !218
  %t1782 = add i32 %t1781, 1, !dbg !218
  store i32 %t1782, ptr %slot1633, !dbg !218
  br label %if.end.566, !dbg !218
if.else.568:
  call void @lua_pushvalue(ptr %L, i32 2), !dbg !219
  %t1783 = call i32 @nupp.wrap.u32(double 0x4014000000000000), !dbg !219
  %t1784 = uitofp i32 %t1783 to double, !dbg !219
  call void @lua_pushnumber(ptr %L, double %t1784), !dbg !219
  %t1785 = load i32, ptr %slot1629, !dbg !219
  %t1786 = uitofp i32 %t1785 to double, !dbg !219
  call void @lua_pushnumber(ptr %L, double %t1786), !dbg !219
  ret i32 3, !dbg !219
if.end.566:
  br label %if.end.541, !dbg !219
if.else.559:
  %t1787 = load i32, ptr %slot1685, !dbg !219
  %t1788 = icmp eq i32 %t1787, 116, !dbg !219
  br i1 %t1788, label %if.then.577, label %if.else.578, !dbg !219
if.then.577:
  %t1789 = call i32 @nupp.wrap.u32(double 0x3FF0000000000000), !dbg !220
  store i32 %t1789, ptr %slot1675, !dbg !220
  %t1790 = call i32 @nupp.wrap.u32(double 0x0000000000000000), !dbg !221
  store i32 %t1790, ptr %slot1791, !dbg !221
  br label %while.head.579, !dbg !222
while.head.579:
  %t1792 = load i32, ptr %slot1791, !dbg !222
  %t1793 = icmp ult i32 %t1792, 4, !dbg !222
  br i1 %t1793, label %while.body.580, label %while.end.581, !dbg !222
while.body.580:
  %t1794 = load i32, ptr %slot1629, !dbg !223
  %t1795 = load i32, ptr %slot1791, !dbg !223
  %t1796 = add i32 %t1794, %t1795, !dbg !223
  store i32 %t1796, ptr %slot1797, !dbg !223
  %t1798 = load i32, ptr %slot1797, !dbg !224
  %t1799 = load i32, ptr %slot20, !dbg !224
  %t1800 = icmp ult i32 %t1798, %t1799, !dbg !224
  br i1 %t1800, label %if.then.583, label %if.else.584, !dbg !224
if.then.583:
  %t1801 = load i32, ptr %slot1797, !dbg !225
  %t1802 = zext i32 %t1801 to i64, !dbg !225
  %t1803 = getelementptr inbounds i8, ptr %t14, i64 %t1802, !dbg !225
  %t1804 = load i8, ptr %t1803, !dbg !225
  %t1805 = zext i8 %t1804 to i32, !dbg !225
  store i32 %t1805, ptr %slot1806, !dbg !225
  %t1807 = load i32, ptr %slot1791, !dbg !226
  store i32 %t1807, ptr %slot1808, !dbg !226
  store i32 0, ptr %slot1809, !dbg !227
  %t1810 = load i32, ptr %slot1808, !dbg !228
  %t1811 = icmp eq i32 %t1810, 0, !dbg !228
  br i1 %t1811, label %if.then.586, label %if.else.587, !dbg !228
if.then.586:
  %t1812 = call i32 @nupp.wrap.u32(double 0x405D000000000000), !dbg !229
  store i32 %t1812, ptr %slot1809, !dbg !229
  br label %if.end.585, !dbg !229
if.else.587:
  %t1813 = load i32, ptr %slot1808, !dbg !229
  %t1814 = icmp eq i32 %t1813, 1, !dbg !229
  br i1 %t1814, label %if.then.588, label %if.else.589, !dbg !229
if.then.588:
  %t1815 = call i32 @nupp.wrap.u32(double 0x405C800000000000), !dbg !230
  store i32 %t1815, ptr %slot1809, !dbg !230
  br label %if.end.585, !dbg !230
if.else.589:
  %t1816 = load i32, ptr %slot1808, !dbg !230
  %t1817 = icmp eq i32 %t1816, 2, !dbg !230
  br i1 %t1817, label %if.then.590, label %if.else.591, !dbg !230
if.then.590:
  %t1818 = call i32 @nupp.wrap.u32(double 0x405D400000000000), !dbg !231
  store i32 %t1818, ptr %slot1809, !dbg !231
  br label %if.end.585, !dbg !231
if.else.591:
  %t1819 = call i32 @nupp.wrap.u32(double 0x4059400000000000), !dbg !232
  store i32 %t1819, ptr %slot1809, !dbg !232
  br label %if.end.585, !dbg !232
if.end.585:
  %t1820 = load i32, ptr %slot1806, !dbg !233
  %t1821 = load i32, ptr %slot1809, !dbg !233
  %t1822 = icmp ne i32 %t1820, %t1821, !dbg !233
  br i1 %t1822, label %if.then.593, label %if.else.594, !dbg !233
if.then.593:
  call void @lua_pushvalue(ptr %L, i32 2), !dbg !234
  %t1823 = call i32 @nupp.wrap.u32(double 0x3FF0000000000000), !dbg !234
  %t1824 = uitofp i32 %t1823 to double, !dbg !234
  call void @lua_pushnumber(ptr %L, double %t1824), !dbg !234
  %t1825 = load i32, ptr %slot1797, !dbg !234
  %t1826 = add i32 %t1825, 1, !dbg !234
  %t1827 = uitofp i32 %t1826 to double, !dbg !234
  call void @lua_pushnumber(ptr %L, double %t1827), !dbg !234
  ret i32 3, !dbg !234
if.else.594:
  br label %if.end.592, !dbg !234
if.end.592:
  br label %if.end.582, !dbg !234
if.else.584:
  call void @lua_pushvalue(ptr %L, i32 2), !dbg !235
  %t1828 = call i32 @nupp.wrap.u32(double 0x3FF0000000000000), !dbg !235
  %t1829 = uitofp i32 %t1828 to double, !dbg !235
  call void @lua_pushnumber(ptr %L, double %t1829), !dbg !235
  %t1830 = load i32, ptr %slot1797, !dbg !235
  %t1831 = add i32 %t1830, 1, !dbg !235
  %t1832 = uitofp i32 %t1831 to double, !dbg !235
  call void @lua_pushnumber(ptr %L, double %t1832), !dbg !235
  ret i32 3, !dbg !235
if.end.582:
  %t1833 = load i32, ptr %slot1791, !dbg !236
  %t1834 = add i32 %t1833, 1, !dbg !236
  store i32 %t1834, ptr %slot1791, !dbg !236
  br label %while.head.579, !dbg !236
while.end.581:
  %t1835 = call i32 @nupp.wrap.u32(double 0x4010000000000000), !dbg !237
  store i32 %t1835, ptr %slot1679, !dbg !237
  %t1836 = load i32, ptr %slot1629, !dbg !238
  %t1837 = add i32 %t1836, 4, !dbg !238
  store i32 %t1837, ptr %slot1629, !dbg !238
  br label %if.end.541, !dbg !238
if.else.578:
  %t1838 = load i32, ptr %slot1685, !dbg !238
  %t1839 = icmp eq i32 %t1838, 102, !dbg !238
  br i1 %t1839, label %if.then.595, label %if.else.596, !dbg !238
if.then.595:
  %t1840 = call i32 @nupp.wrap.u32(double 0x4000000000000000), !dbg !239
  store i32 %t1840, ptr %slot1675, !dbg !239
  %t1841 = call i32 @nupp.wrap.u32(double 0x0000000000000000), !dbg !240
  store i32 %t1841, ptr %slot1842, !dbg !240
  br label %while.head.597, !dbg !241
while.head.597:
  %t1843 = load i32, ptr %slot1842, !dbg !241
  %t1844 = icmp ult i32 %t1843, 5, !dbg !241
  br i1 %t1844, label %while.body.598, label %while.end.599, !dbg !241
while.body.598:
  %t1845 = load i32, ptr %slot1629, !dbg !242
  %t1846 = load i32, ptr %slot1842, !dbg !242
  %t1847 = add i32 %t1845, %t1846, !dbg !242
  store i32 %t1847, ptr %slot1848, !dbg !242
  %t1849 = load i32, ptr %slot1848, !dbg !243
  %t1850 = load i32, ptr %slot20, !dbg !243
  %t1851 = icmp ult i32 %t1849, %t1850, !dbg !243
  br i1 %t1851, label %if.then.601, label %if.else.602, !dbg !243
if.then.601:
  %t1852 = load i32, ptr %slot1848, !dbg !244
  %t1853 = zext i32 %t1852 to i64, !dbg !244
  %t1854 = getelementptr inbounds i8, ptr %t14, i64 %t1853, !dbg !244
  %t1855 = load i8, ptr %t1854, !dbg !244
  %t1856 = zext i8 %t1855 to i32, !dbg !244
  store i32 %t1856, ptr %slot1857, !dbg !244
  %t1858 = load i32, ptr %slot1842, !dbg !245
  store i32 %t1858, ptr %slot1859, !dbg !245
  store i32 0, ptr %slot1860, !dbg !246
  %t1861 = load i32, ptr %slot1859, !dbg !247
  %t1862 = icmp eq i32 %t1861, 0, !dbg !247
  br i1 %t1862, label %if.then.604, label %if.else.605, !dbg !247
if.then.604:
  %t1863 = call i32 @nupp.wrap.u32(double 0x4059800000000000), !dbg !248
  store i32 %t1863, ptr %slot1860, !dbg !248
  br label %if.end.603, !dbg !248
if.else.605:
  %t1864 = load i32, ptr %slot1859, !dbg !248
  %t1865 = icmp eq i32 %t1864, 1, !dbg !248
  br i1 %t1865, label %if.then.606, label %if.else.607, !dbg !248
if.then.606:
  %t1866 = call i32 @nupp.wrap.u32(double 0x4058400000000000), !dbg !249
  store i32 %t1866, ptr %slot1860, !dbg !249
  br label %if.end.603, !dbg !249
if.else.607:
  %t1867 = load i32, ptr %slot1859, !dbg !249
  %t1868 = icmp eq i32 %t1867, 2, !dbg !249
  br i1 %t1868, label %if.then.608, label %if.else.609, !dbg !249
if.then.608:
  %t1869 = call i32 @nupp.wrap.u32(double 0x405B000000000000), !dbg !250
  store i32 %t1869, ptr %slot1860, !dbg !250
  br label %if.end.603, !dbg !250
if.else.609:
  %t1870 = load i32, ptr %slot1859, !dbg !250
  %t1871 = icmp eq i32 %t1870, 3, !dbg !250
  br i1 %t1871, label %if.then.610, label %if.else.611, !dbg !250
if.then.610:
  %t1872 = call i32 @nupp.wrap.u32(double 0x405CC00000000000), !dbg !251
  store i32 %t1872, ptr %slot1860, !dbg !251
  br label %if.end.603, !dbg !251
if.else.611:
  %t1873 = call i32 @nupp.wrap.u32(double 0x4059400000000000), !dbg !252
  store i32 %t1873, ptr %slot1860, !dbg !252
  br label %if.end.603, !dbg !252
if.end.603:
  %t1874 = load i32, ptr %slot1857, !dbg !253
  %t1875 = load i32, ptr %slot1860, !dbg !253
  %t1876 = icmp ne i32 %t1874, %t1875, !dbg !253
  br i1 %t1876, label %if.then.613, label %if.else.614, !dbg !253
if.then.613:
  call void @lua_pushvalue(ptr %L, i32 2), !dbg !254
  %t1877 = call i32 @nupp.wrap.u32(double 0x3FF0000000000000), !dbg !254
  %t1878 = uitofp i32 %t1877 to double, !dbg !254
  call void @lua_pushnumber(ptr %L, double %t1878), !dbg !254
  %t1879 = load i32, ptr %slot1848, !dbg !254
  %t1880 = add i32 %t1879, 1, !dbg !254
  %t1881 = uitofp i32 %t1880 to double, !dbg !254
  call void @lua_pushnumber(ptr %L, double %t1881), !dbg !254
  ret i32 3, !dbg !254
if.else.614:
  br label %if.end.612, !dbg !254
if.end.612:
  br label %if.end.600, !dbg !254
if.else.602:
  call void @lua_pushvalue(ptr %L, i32 2), !dbg !255
  %t1882 = call i32 @nupp.wrap.u32(double 0x3FF0000000000000), !dbg !255
  %t1883 = uitofp i32 %t1882 to double, !dbg !255
  call void @lua_pushnumber(ptr %L, double %t1883), !dbg !255
  %t1884 = load i32, ptr %slot1848, !dbg !255
  %t1885 = add i32 %t1884, 1, !dbg !255
  %t1886 = uitofp i32 %t1885 to double, !dbg !255
  call void @lua_pushnumber(ptr %L, double %t1886), !dbg !255
  ret i32 3, !dbg !255
if.end.600:
  %t1887 = load i32, ptr %slot1842, !dbg !256
  %t1888 = add i32 %t1887, 1, !dbg !256
  store i32 %t1888, ptr %slot1842, !dbg !256
  br label %while.head.597, !dbg !256
while.end.599:
  %t1889 = call i32 @nupp.wrap.u32(double 0x4014000000000000), !dbg !257
  store i32 %t1889, ptr %slot1679, !dbg !257
  %t1890 = load i32, ptr %slot1629, !dbg !258
  %t1891 = add i32 %t1890, 5, !dbg !258
  store i32 %t1891, ptr %slot1629, !dbg !258
  br label %if.end.541, !dbg !258
if.else.596:
  %t1892 = load i32, ptr %slot1685, !dbg !258
  %t1893 = icmp eq i32 %t1892, 110, !dbg !258
  br i1 %t1893, label %if.then.615, label %if.else.616, !dbg !258
if.then.615:
  %t1894 = call i32 @nupp.wrap.u32(double 0x0000000000000000), !dbg !259
  store i32 %t1894, ptr %slot1675, !dbg !259
  %t1895 = call i32 @nupp.wrap.u32(double 0x0000000000000000), !dbg !260
  store i32 %t1895, ptr %slot1896, !dbg !260
  br label %while.head.617, !dbg !261
while.head.617:
  %t1897 = load i32, ptr %slot1896, !dbg !261
  %t1898 = icmp ult i32 %t1897, 4, !dbg !261
  br i1 %t1898, label %while.body.618, label %while.end.619, !dbg !261
while.body.618:
  %t1899 = load i32, ptr %slot1629, !dbg !262
  %t1900 = load i32, ptr %slot1896, !dbg !262
  %t1901 = add i32 %t1899, %t1900, !dbg !262
  store i32 %t1901, ptr %slot1902, !dbg !262
  %t1903 = load i32, ptr %slot1902, !dbg !263
  %t1904 = load i32, ptr %slot20, !dbg !263
  %t1905 = icmp ult i32 %t1903, %t1904, !dbg !263
  br i1 %t1905, label %if.then.621, label %if.else.622, !dbg !263
if.then.621:
  %t1906 = load i32, ptr %slot1902, !dbg !264
  %t1907 = zext i32 %t1906 to i64, !dbg !264
  %t1908 = getelementptr inbounds i8, ptr %t14, i64 %t1907, !dbg !264
  %t1909 = load i8, ptr %t1908, !dbg !264
  %t1910 = zext i8 %t1909 to i32, !dbg !264
  store i32 %t1910, ptr %slot1911, !dbg !264
  %t1912 = load i32, ptr %slot1896, !dbg !265
  store i32 %t1912, ptr %slot1913, !dbg !265
  store i32 0, ptr %slot1914, !dbg !266
  %t1915 = load i32, ptr %slot1913, !dbg !267
  %t1916 = icmp eq i32 %t1915, 0, !dbg !267
  br i1 %t1916, label %if.then.624, label %if.else.625, !dbg !267
if.then.624:
  %t1917 = call i32 @nupp.wrap.u32(double 0x405B800000000000), !dbg !268
  store i32 %t1917, ptr %slot1914, !dbg !268
  br label %if.end.623, !dbg !268
if.else.625:
  %t1918 = load i32, ptr %slot1913, !dbg !268
  %t1919 = icmp eq i32 %t1918, 1, !dbg !268
  br i1 %t1919, label %if.then.626, label %if.else.627, !dbg !268
if.then.626:
  %t1920 = call i32 @nupp.wrap.u32(double 0x405D400000000000), !dbg !269
  store i32 %t1920, ptr %slot1914, !dbg !269
  br label %if.end.623, !dbg !269
if.else.627:
  %t1921 = call i32 @nupp.wrap.u32(double 0x405B000000000000), !dbg !270
  store i32 %t1921, ptr %slot1914, !dbg !270
  br label %if.end.623, !dbg !270
if.end.623:
  %t1922 = load i32, ptr %slot1911, !dbg !271
  %t1923 = load i32, ptr %slot1914, !dbg !271
  %t1924 = icmp ne i32 %t1922, %t1923, !dbg !271
  br i1 %t1924, label %if.then.629, label %if.else.630, !dbg !271
if.then.629:
  call void @lua_pushvalue(ptr %L, i32 2), !dbg !272
  %t1925 = call i32 @nupp.wrap.u32(double 0x3FF0000000000000), !dbg !272
  %t1926 = uitofp i32 %t1925 to double, !dbg !272
  call void @lua_pushnumber(ptr %L, double %t1926), !dbg !272
  %t1927 = load i32, ptr %slot1902, !dbg !272
  %t1928 = add i32 %t1927, 1, !dbg !272
  %t1929 = uitofp i32 %t1928 to double, !dbg !272
  call void @lua_pushnumber(ptr %L, double %t1929), !dbg !272
  ret i32 3, !dbg !272
if.else.630:
  br label %if.end.628, !dbg !272
if.end.628:
  br label %if.end.620, !dbg !272
if.else.622:
  call void @lua_pushvalue(ptr %L, i32 2), !dbg !273
  %t1930 = call i32 @nupp.wrap.u32(double 0x3FF0000000000000), !dbg !273
  %t1931 = uitofp i32 %t1930 to double, !dbg !273
  call void @lua_pushnumber(ptr %L, double %t1931), !dbg !273
  %t1932 = load i32, ptr %slot1902, !dbg !273
  %t1933 = add i32 %t1932, 1, !dbg !273
  %t1934 = uitofp i32 %t1933 to double, !dbg !273
  call void @lua_pushnumber(ptr %L, double %t1934), !dbg !273
  ret i32 3, !dbg !273
if.end.620:
  %t1935 = load i32, ptr %slot1896, !dbg !274
  %t1936 = add i32 %t1935, 1, !dbg !274
  store i32 %t1936, ptr %slot1896, !dbg !274
  br label %while.head.617, !dbg !274
while.end.619:
  %t1937 = call i32 @nupp.wrap.u32(double 0x4010000000000000), !dbg !275
  store i32 %t1937, ptr %slot1679, !dbg !275
  %t1938 = load i32, ptr %slot1629, !dbg !276
  %t1939 = add i32 %t1938, 4, !dbg !276
  store i32 %t1939, ptr %slot1629, !dbg !276
  br label %if.end.541, !dbg !276
if.else.616:
  %t1940 = load i32, ptr %slot1685, !dbg !276
  %t1941 = icmp eq i32 %t1940, 45, !dbg !276
  br i1 %t1941, label %or.end.632, label %or.rhs.631, !dbg !276
or.rhs.631:
  %t1942 = load i32, ptr %slot1685, !dbg !276
  %t1943 = icmp uge i32 %t1942, 48, !dbg !276
  br i1 %t1943, label %and.rhs.633, label %and.end.634, !dbg !276
and.rhs.633:
  %t1944 = load i32, ptr %slot1685, !dbg !276
  %t1945 = icmp ule i32 %t1944, 57, !dbg !276
  br label %and.end.634, !dbg !276
and.end.634:
  %t1946 = phi i1 [ false, %or.rhs.631 ], [ %t1945, %and.rhs.633 ], !dbg !276
  br label %or.end.632, !dbg !276
or.end.632:
  %t1947 = phi i1 [ true, %if.else.616 ], [ %t1946, %and.end.634 ], !dbg !276
  br i1 %t1947, label %if.then.635, label %if.else.636, !dbg !276
if.then.635:
  %t1948 = call i32 @nupp.wrap.u32(double 0x4008000000000000), !dbg !277
  store i32 %t1948, ptr %slot1675, !dbg !277
  %t1949 = load i32, ptr %slot1629, !dbg !278
  %t1950 = zext i32 %t1949 to i64, !dbg !278
  %t1951 = load i32, ptr %slot20, !dbg !278
  %t1952 = zext i32 %t1951 to i64, !dbg !278
  %t1953 = getelementptr inbounds ptr, ptr %t1, i64 64, !dbg !278
  %rt.builder_number_token.1954 = load ptr, ptr %t1953, !invariant.load !8, !dbg !278
  %t1955 = call i64 %rt.builder_number_token.1954(ptr %L, ptr %slot1618, ptr %t14, i64 %t15, i64 %t1950, i64 %t1952, i64 1), !dbg !278
  %t1956 = trunc i64 %t1955 to i32, !dbg !278
  store i32 %t1956, ptr %slot1957, !dbg !278
  %t1958 = load i32, ptr %slot1957, !dbg !279
  %t1959 = icmp ult i32 %t1958, 2147483648, !dbg !279
  br i1 %t1959, label %if.then.638, label %if.else.639, !dbg !279
if.then.638:
  call void @lua_pushvalue(ptr %L, i32 2), !dbg !280
  %t1960 = call i32 @nupp.wrap.u32(double 0x3FF0000000000000), !dbg !280
  %t1961 = uitofp i32 %t1960 to double, !dbg !280
  call void @lua_pushnumber(ptr %L, double %t1961), !dbg !280
  %t1962 = load i32, ptr %slot1957, !dbg !280
  %t1963 = uitofp i32 %t1962 to double, !dbg !280
  call void @lua_pushnumber(ptr %L, double %t1963), !dbg !280
  ret i32 3, !dbg !280
if.else.639:
  br label %if.end.637, !dbg !280
if.end.637:
  %t1964 = load i32, ptr %slot1957, !dbg !281
  %t1965 = sub i32 %t1964, 2147483648, !dbg !281
  store i32 %t1965, ptr %slot1629, !dbg !281
  %t1966 = load i32, ptr %slot1629, !dbg !282
  %t1967 = load i32, ptr %slot1677, !dbg !282
  %t1968 = sub i32 %t1966, %t1967, !dbg !282
  store i32 %t1968, ptr %slot1679, !dbg !282
  br label %if.end.541, !dbg !282
if.else.636:
  call void @lua_pushvalue(ptr %L, i32 2), !dbg !283
  %t1969 = call i32 @nupp.wrap.u32(double 0x3FF0000000000000), !dbg !283
  %t1970 = uitofp i32 %t1969 to double, !dbg !283
  call void @lua_pushnumber(ptr %L, double %t1970), !dbg !283
  %t1971 = load i32, ptr %slot1629, !dbg !283
  %t1972 = add i32 %t1971, 1, !dbg !283
  %t1973 = uitofp i32 %t1972 to double, !dbg !283
  call void @lua_pushnumber(ptr %L, double %t1973), !dbg !283
  ret i32 3, !dbg !283
if.end.541:
  %t1974 = load i32, ptr %slot1675, !dbg !284
  %t1975 = icmp eq i32 %t1974, 0, !dbg !284
  br i1 %t1975, label %if.then.641, label %if.else.642, !dbg !284
if.then.641:
  %t1976 = getelementptr inbounds ptr, ptr %t1, i64 57, !dbg !285
  %rt.builder_null.1977 = load ptr, ptr %t1976, !invariant.load !8, !dbg !285
  call void %rt.builder_null.1977(ptr %L, ptr %slot1618, i64 1), !dbg !285
  br label %if.end.640, !dbg !285
if.else.642:
  %t1978 = load i32, ptr %slot1675, !dbg !285
  %t1979 = icmp eq i32 %t1978, 1, !dbg !285
  br i1 %t1979, label %if.then.643, label %if.else.644, !dbg !285
if.then.643:
  %t1980 = zext i1 true to i64, !dbg !286
  %t1981 = getelementptr inbounds ptr, ptr %t1, i64 56, !dbg !286
  %rt.builder_boolean.1982 = load ptr, ptr %t1981, !invariant.load !8, !dbg !286
  call void %rt.builder_boolean.1982(ptr %L, ptr %slot1618, i64 %t1980, i64 1), !dbg !286
  br label %if.end.640, !dbg !286
if.else.644:
  %t1983 = load i32, ptr %slot1675, !dbg !286
  %t1984 = icmp eq i32 %t1983, 2, !dbg !286
  br i1 %t1984, label %if.then.645, label %if.else.646, !dbg !286
if.then.645:
  %t1985 = zext i1 false to i64, !dbg !287
  %t1986 = getelementptr inbounds ptr, ptr %t1, i64 56, !dbg !287
  %rt.builder_boolean.1987 = load ptr, ptr %t1986, !invariant.load !8, !dbg !287
  call void %rt.builder_boolean.1987(ptr %L, ptr %slot1618, i64 %t1985, i64 1), !dbg !287
  br label %if.end.640, !dbg !287
if.else.646:
  %t1988 = load i32, ptr %slot1675, !dbg !287
  %t1989 = icmp eq i32 %t1988, 4, !dbg !287
  br i1 %t1989, label %if.then.647, label %if.else.648, !dbg !287
if.then.647:
  %t1990 = load i32, ptr %slot1677, !dbg !288
  %t1991 = zext i32 %t1990 to i64, !dbg !288
  %t1992 = load i32, ptr %slot1679, !dbg !288
  %t1993 = zext i32 %t1992 to i64, !dbg !288
  %t1994 = load i32, ptr %slot1681, !dbg !288
  %t1995 = icmp eq i32 %t1994, 1, !dbg !288
  %t1996 = zext i1 %t1995 to i64, !dbg !288
  %t1997 = getelementptr inbounds ptr, ptr %t1, i64 49, !dbg !288
  %rt.builder_string.1998 = load ptr, ptr %t1997, !invariant.load !8, !dbg !288
  call void %rt.builder_string.1998(ptr %L, ptr %slot1618, ptr %t14, i64 %t15, i64 %t1991, i64 %t1993, i64 %t1996, i64 0, i64 1), !dbg !288
  br label %if.end.640, !dbg !288
if.else.648:
  %t1999 = load i32, ptr %slot1675, !dbg !288
  %t2000 = icmp eq i32 %t1999, 5, !dbg !288
  br i1 %t2000, label %if.then.649, label %if.else.650, !dbg !288
if.then.649:
  %t2001 = load i32, ptr %slot1683, !dbg !289
  %t2002 = zext i32 %t2001 to i64, !dbg !289
  %t2003 = getelementptr inbounds ptr, ptr %t1, i64 48, !dbg !289
  %rt.builder_open.2004 = load ptr, ptr %t2003, !invariant.load !8, !dbg !289
  call void %rt.builder_open.2004(ptr %L, ptr %slot1618, i64 5, i64 %t2002, i64 1), !dbg !289
  br label %if.end.640, !dbg !289
if.else.650:
  %t2005 = load i32, ptr %slot1675, !dbg !289
  %t2006 = icmp eq i32 %t2005, 6, !dbg !289
  br i1 %t2006, label %if.then.651, label %if.else.652, !dbg !289
if.then.651:
  %t2007 = load i32, ptr %slot1683, !dbg !290
  %t2008 = zext i32 %t2007 to i64, !dbg !290
  %t2009 = getelementptr inbounds ptr, ptr %t1, i64 48, !dbg !290
  %rt.builder_open.2010 = load ptr, ptr %t2009, !invariant.load !8, !dbg !290
  call void %rt.builder_open.2010(ptr %L, ptr %slot1618, i64 6, i64 %t2008, i64 1), !dbg !290
  br label %if.end.640, !dbg !290
if.else.652:
  br label %if.end.640, !dbg !290
if.end.640:
  store i1 false, ptr %slot1634, !dbg !291
  br label %if.end.535, !dbg !291
if.else.537:
  %t2011 = getelementptr inbounds { [10 x i32], i32, i32, i32, i32, i32, i32, ptr, [16 x { i32, i32, i32, i32, i32, i32, i32, i32, i64, i32, i32, i32, i32 }] }, ptr %slot1618, i32 0, i32 1, !dbg !291
  %t2012 = load i32, ptr %t2011, !dbg !291
  %t2013 = icmp eq i32 %t2012, 0, !dbg !291
  br i1 %t2013, label %if.then.653, label %if.else.654, !dbg !291
if.then.653:
  %t2014 = load i32, ptr %slot1629, !dbg !292
  %t2015 = load i32, ptr %slot20, !dbg !292
  %t2016 = icmp ult i32 %t2014, %t2015, !dbg !292
  br i1 %t2016, label %if.then.656, label %if.else.657, !dbg !292
if.then.656:
  call void @lua_pushvalue(ptr %L, i32 2), !dbg !293
  %t2017 = call i32 @nupp.wrap.u32(double 0x3FF0000000000000), !dbg !293
  %t2018 = uitofp i32 %t2017 to double, !dbg !293
  call void @lua_pushnumber(ptr %L, double %t2018), !dbg !293
  %t2019 = load i32, ptr %slot1629, !dbg !293
  %t2020 = add i32 %t2019, 1, !dbg !293
  %t2021 = uitofp i32 %t2020 to double, !dbg !293
  call void @lua_pushnumber(ptr %L, double %t2021), !dbg !293
  ret i32 3, !dbg !293
if.else.657:
  br label %if.end.655, !dbg !293
if.end.655:
  store i1 true, ptr %slot1635, !dbg !294
  br label %if.end.535, !dbg !294
if.else.654:
  %t2022 = load i32, ptr %slot1629, !dbg !295
  %t2023 = load i32, ptr %slot20, !dbg !295
  %t2024 = icmp uge i32 %t2022, %t2023, !dbg !295
  br i1 %t2024, label %if.then.659, label %if.else.660, !dbg !295
if.then.659:
  call void @lua_pushvalue(ptr %L, i32 2), !dbg !296
  %t2025 = call i32 @nupp.wrap.u32(double 0x3FF0000000000000), !dbg !296
  %t2026 = uitofp i32 %t2025 to double, !dbg !296
  call void @lua_pushnumber(ptr %L, double %t2026), !dbg !296
  %t2027 = load i32, ptr %slot1629, !dbg !296
  %t2028 = add i32 %t2027, 1, !dbg !296
  %t2029 = uitofp i32 %t2028 to double, !dbg !296
  call void @lua_pushnumber(ptr %L, double %t2029), !dbg !296
  ret i32 3, !dbg !296
if.else.660:
  br label %if.end.658, !dbg !296
if.end.658:
  %t2030 = getelementptr inbounds { [10 x i32], i32, i32, i32, i32, i32, i32, ptr, [16 x { i32, i32, i32, i32, i32, i32, i32, i32, i64, i32, i32, i32, i32 }] }, ptr %slot1618, i32 0, i32 1, !dbg !297
  %t2031 = load i32, ptr %t2030, !dbg !297
  %t2032 = icmp eq i32 %t2031, 0, !dbg !297
  store i32 0, ptr %slot2033, !dbg !297
  br i1 %t2032, label %lua.state.662, label %lua.frame.661, !dbg !297
lua.frame.661:
  %t2034 = getelementptr inbounds { [10 x i32], i32, i32, i32, i32, i32, i32, ptr, [16 x { i32, i32, i32, i32, i32, i32, i32, i32, i64, i32, i32, i32, i32 }] }, ptr %slot1618, i32 0, i32 7, !dbg !297
  %t2035 = load ptr, ptr %t2034, !dbg !297
  %t2036 = getelementptr inbounds { [10 x i32], i32, i32, i32, i32, i32, i32, ptr, [16 x { i32, i32, i32, i32, i32, i32, i32, i32, i64, i32, i32, i32, i32 }] }, ptr %slot1618, i32 0, i32 8, !dbg !297
  %t2037 = icmp eq ptr %t2035, null, !dbg !297
  %t2038 = select i1 %t2037, ptr %t2036, ptr %t2035, !dbg !297
  %t2039 = sub i32 %t2031, 1, !dbg !297
  %t2040 = zext i32 %t2039 to i64, !dbg !297
  %t2041 = getelementptr inbounds { i32, i32, i32, i32, i32, i32, i32, i32, i64, i32, i32, i32, i32 }, ptr %t2038, i64 %t2040, !dbg !297
  %t2042 = getelementptr inbounds { i32, i32, i32, i32, i32, i32, i32, i32, i64, i32, i32, i32, i32 }, ptr %t2041, i32 0, i32 2, !dbg !297
  %t2043 = load i32, ptr %t2042, !dbg !297
  %t2044 = getelementptr inbounds { i32, i32, i32, i32, i32, i32, i32, i32, i64, i32, i32, i32, i32 }, ptr %t2041, i32 0, i32 4, !dbg !297
  %t2045 = load i32, ptr %t2044, !dbg !297
  %t2046 = icmp ne i32 %t2045, 0, !dbg !297
  %t2047 = select i1 %t2046, i32 256, i32 0, !dbg !297
  %t2048 = or i32 %t2043, %t2047, !dbg !297
  store i32 %t2048, ptr %slot2033, !dbg !297
  br label %lua.state.662, !dbg !297
lua.state.662:
  %t2049 = load i32, ptr %slot2033, !dbg !297
  store i32 %t2049, ptr %slot2050, !dbg !297
  %t2051 = load i32, ptr %slot1637, !dbg !298
  store i32 %t2051, ptr %slot2052, !dbg !298
  %t2053 = load i32, ptr %slot2050, !dbg !299
  %t2054 = and i32 %t2053, 255, !dbg !299
  store i32 %t2054, ptr %slot2055, !dbg !299
  %t2056 = load i32, ptr %slot2050, !dbg !300
  %t2057 = and i32 %t2056, 256, !dbg !300
  %t2058 = icmp ne i32 %t2057, 0, !dbg !300
  store i1 %t2058, ptr %slot2059, !dbg !300
  %t2060 = load i32, ptr %slot2055, !dbg !301
  %t2061 = icmp eq i32 %t2060, 5, !dbg !301
  br i1 %t2061, label %and.rhs.663, label %and.end.664, !dbg !301
and.rhs.663:
  %t2062 = load i32, ptr %slot2052, !dbg !301
  %t2063 = icmp eq i32 %t2062, 93, !dbg !301
  br label %and.end.664, !dbg !301
and.end.664:
  %t2064 = phi i1 [ false, %lua.state.662 ], [ %t2063, %and.rhs.663 ], !dbg !301
  br i1 %t2064, label %or.end.666, label %or.rhs.665, !dbg !301
or.rhs.665:
  %t2065 = load i32, ptr %slot2055, !dbg !301
  %t2066 = icmp eq i32 %t2065, 6, !dbg !301
  br i1 %t2066, label %and.rhs.667, label %and.end.668, !dbg !301
and.rhs.667:
  %t2067 = load i32, ptr %slot2052, !dbg !301
  %t2068 = icmp eq i32 %t2067, 125, !dbg !301
  br label %and.end.668, !dbg !301
and.end.668:
  %t2069 = phi i1 [ false, %or.rhs.665 ], [ %t2068, %and.rhs.667 ], !dbg !301
  br label %or.end.666, !dbg !301
or.end.666:
  %t2070 = phi i1 [ true, %and.end.664 ], [ %t2069, %and.end.668 ], !dbg !301
  store i1 %t2070, ptr %slot2071, !dbg !301
  %t2072 = load i1, ptr %slot2071, !dbg !302
  br i1 %t2072, label %if.then.670, label %if.else.671, !dbg !302
if.then.670:
  %t2073 = load i32, ptr %slot1633, !dbg !303
  %t2074 = load i32, ptr %slot35, !dbg !303
  %t2075 = icmp uge i32 %t2073, %t2074, !dbg !303
  br i1 %t2075, label %or.end.674, label %or.rhs.673, !dbg !303
or.rhs.673:
  %t2076 = load i32, ptr %slot1633, !dbg !303
  %t2077 = getelementptr inbounds { ptr, i32, i32, i32, i32, [32 x i32] }, ptr %slot27, i32 0, i32 0, !dbg !303
  %t2078 = load ptr, ptr %t2077, !dbg !303
  %t2079 = zext i32 %t2076 to i64, !dbg !303
  %t2080 = getelementptr inbounds i32, ptr %t2078, i64 %t2079, !dbg !303
  %t2081 = load i32, ptr %t2080, !dbg !303
  %t2082 = load i32, ptr %slot1629, !dbg !303
  %t2083 = icmp ne i32 %t2081, %t2082, !dbg !303
  br label %or.end.674, !dbg !303
or.end.674:
  %t2084 = phi i1 [ true, %if.then.670 ], [ %t2083, %or.rhs.673 ], !dbg !303
  br i1 %t2084, label %if.then.675, label %if.else.676, !dbg !303
if.then.675:
  call void @lua_pushvalue(ptr %L, i32 2), !dbg !304
  %t2085 = call i32 @nupp.wrap.u32(double 0x4014000000000000), !dbg !304
  %t2086 = uitofp i32 %t2085 to double, !dbg !304
  call void @lua_pushnumber(ptr %L, double %t2086), !dbg !304
  %t2087 = load i32, ptr %slot1629, !dbg !304
  %t2088 = add i32 %t2087, 1, !dbg !304
  %t2089 = uitofp i32 %t2088 to double, !dbg !304
  call void @lua_pushnumber(ptr %L, double %t2089), !dbg !304
  ret i32 3, !dbg !304
if.else.676:
  br label %if.end.672, !dbg !304
if.end.672:
  %t2090 = load i32, ptr %slot1633, !dbg !305
  %t2091 = add i32 %t2090, 1, !dbg !305
  store i32 %t2091, ptr %slot1633, !dbg !305
  %t2092 = load i32, ptr %slot1629, !dbg !306
  %t2093 = add i32 %t2092, 1, !dbg !306
  store i32 %t2093, ptr %slot1629, !dbg !306
  %t2094 = getelementptr inbounds ptr, ptr %t1, i64 58, !dbg !307
  %rt.builder_close.2095 = load ptr, ptr %t2094, !invariant.load !8, !dbg !307
  call void %rt.builder_close.2095(ptr %L, ptr %slot1618, i64 1), !dbg !307
  br label %if.end.669, !dbg !307
if.else.671:
  %t2096 = load i32, ptr %slot2055, !dbg !307
  %t2097 = icmp eq i32 %t2096, 5, !dbg !307
  br i1 %t2097, label %if.then.677, label %if.else.678, !dbg !307
if.then.677:
  %t2098 = load i1, ptr %slot2059, !dbg !308
  %t2099 = xor i1 %t2098, true, !dbg !308
  br i1 %t2099, label %if.then.680, label %if.else.681, !dbg !308
if.then.680:
  store i1 true, ptr %slot1634, !dbg !309
  br label %if.end.679, !dbg !309
if.else.681:
  %t2100 = load i32, ptr %slot2052, !dbg !309
  %t2101 = icmp eq i32 %t2100, 44, !dbg !309
  br i1 %t2101, label %if.then.682, label %if.else.683, !dbg !309
if.then.682:
  %t2102 = load i32, ptr %slot1629, !dbg !310
  %t2103 = add i32 %t2102, 1, !dbg !310
  store i32 %t2103, ptr %slot1629, !dbg !310
  %t2104 = load i32, ptr %slot1633, !dbg !311
  %t2105 = load i32, ptr %slot35, !dbg !311
  %t2106 = icmp uge i32 %t2104, %t2105, !dbg !311
  br i1 %t2106, label %if.then.685, label %if.else.686, !dbg !311
if.then.685:
  call void @lua_pushvalue(ptr %L, i32 2), !dbg !312
  %t2107 = call i32 @nupp.wrap.u32(double 0x4014000000000000), !dbg !312
  %t2108 = uitofp i32 %t2107 to double, !dbg !312
  call void @lua_pushnumber(ptr %L, double %t2108), !dbg !312
  %t2109 = load i32, ptr %slot1629, !dbg !312
  %t2110 = uitofp i32 %t2109 to double, !dbg !312
  call void @lua_pushnumber(ptr %L, double %t2110), !dbg !312
  ret i32 3, !dbg !312
if.else.686:
  br label %if.end.684, !dbg !312
if.end.684:
  %t2111 = load i32, ptr %slot1633, !dbg !313
  %t2112 = add i32 %t2111, 1, !dbg !313
  store i32 %t2112, ptr %slot1633, !dbg !313
  store i1 true, ptr %slot1634, !dbg !314
  br label %if.end.679, !dbg !314
if.else.683:
  call void @lua_pushvalue(ptr %L, i32 2), !dbg !315
  %t2113 = call i32 @nupp.wrap.u32(double 0x3FF0000000000000), !dbg !315
  %t2114 = uitofp i32 %t2113 to double, !dbg !315
  call void @lua_pushnumber(ptr %L, double %t2114), !dbg !315
  %t2115 = load i32, ptr %slot1629, !dbg !315
  %t2116 = add i32 %t2115, 1, !dbg !315
  %t2117 = uitofp i32 %t2116 to double, !dbg !315
  call void @lua_pushnumber(ptr %L, double %t2117), !dbg !315
  ret i32 3, !dbg !315
if.end.679:
  br label %if.end.669, !dbg !315
if.else.678:
  %t2118 = load i1, ptr %slot2059, !dbg !316
  br i1 %t2118, label %if.then.688, label %if.else.689, !dbg !316
if.then.688:
  %t2119 = load i32, ptr %slot2052, !dbg !317
  %t2120 = icmp ne i32 %t2119, 44, !dbg !317
  br i1 %t2120, label %if.then.691, label %if.else.692, !dbg !317
if.then.691:
  call void @lua_pushvalue(ptr %L, i32 2), !dbg !318
  %t2121 = call i32 @nupp.wrap.u32(double 0x3FF0000000000000), !dbg !318
  %t2122 = uitofp i32 %t2121 to double, !dbg !318
  call void @lua_pushnumber(ptr %L, double %t2122), !dbg !318
  %t2123 = load i32, ptr %slot1629, !dbg !318
  %t2124 = add i32 %t2123, 1, !dbg !318
  %t2125 = uitofp i32 %t2124 to double, !dbg !318
  call void @lua_pushnumber(ptr %L, double %t2125), !dbg !318
  ret i32 3, !dbg !318
if.else.692:
  br label %if.end.690, !dbg !318
if.end.690:
  %t2126 = load i32, ptr %slot1629, !dbg !319
  %t2127 = add i32 %t2126, 1, !dbg !319
  store i32 %t2127, ptr %slot1629, !dbg !319
  %t2128 = load i32, ptr %slot1633, !dbg !320
  %t2129 = load i32, ptr %slot35, !dbg !320
  %t2130 = icmp uge i32 %t2128, %t2129, !dbg !320
  br i1 %t2130, label %if.then.694, label %if.else.695, !dbg !320
if.then.694:
  call void @lua_pushvalue(ptr %L, i32 2), !dbg !321
  %t2131 = call i32 @nupp.wrap.u32(double 0x4014000000000000), !dbg !321
  %t2132 = uitofp i32 %t2131 to double, !dbg !321
  call void @lua_pushnumber(ptr %L, double %t2132), !dbg !321
  %t2133 = load i32, ptr %slot1629, !dbg !321
  %t2134 = uitofp i32 %t2133 to double, !dbg !321
  call void @lua_pushnumber(ptr %L, double %t2134), !dbg !321
  ret i32 3, !dbg !321
if.else.695:
  br label %if.end.693, !dbg !321
if.end.693:
  %t2135 = load i32, ptr %slot1633, !dbg !322
  %t2136 = add i32 %t2135, 1, !dbg !322
  store i32 %t2136, ptr %slot1633, !dbg !322
  store i1 true, ptr %slot2137, !dbg !323
  br label %while.head.696, !dbg !324
while.head.696:
  %t2138 = load i1, ptr %slot2137, !dbg !324
  br i1 %t2138, label %and.rhs.699, label %and.end.700, !dbg !324
and.rhs.699:
  %t2139 = load i32, ptr %slot1629, !dbg !324
  %t2140 = load i32, ptr %slot20, !dbg !324
  %t2141 = icmp ult i32 %t2139, %t2140, !dbg !324
  br label %and.end.700, !dbg !324
and.end.700:
  %t2142 = phi i1 [ false, %while.head.696 ], [ %t2141, %and.rhs.699 ], !dbg !324
  br i1 %t2142, label %while.body.697, label %while.end.698, !dbg !324
while.body.697:
  %t2143 = load i32, ptr %slot1629, !dbg !325
  %t2144 = zext i32 %t2143 to i64, !dbg !325
  %t2145 = getelementptr inbounds i8, ptr %t14, i64 %t2144, !dbg !325
  %t2146 = load i8, ptr %t2145, !dbg !325
  %t2147 = zext i8 %t2146 to i32, !dbg !325
  store i32 %t2147, ptr %slot2148, !dbg !325
  %t2149 = load i32, ptr %slot2148, !dbg !326
  %t2150 = icmp eq i32 %t2149, 32, !dbg !326
  br i1 %t2150, label %or.end.703, label %or.rhs.702, !dbg !326
or.rhs.702:
  %t2151 = load i32, ptr %slot2148, !dbg !326
  %t2152 = icmp eq i32 %t2151, 9, !dbg !326
  br label %or.end.703, !dbg !326
or.end.703:
  %t2153 = phi i1 [ true, %while.body.697 ], [ %t2152, %or.rhs.702 ], !dbg !326
  br i1 %t2153, label %or.end.705, label %or.rhs.704, !dbg !326
or.rhs.704:
  %t2154 = load i32, ptr %slot2148, !dbg !326
  %t2155 = icmp eq i32 %t2154, 10, !dbg !326
  br label %or.end.705, !dbg !326
or.end.705:
  %t2156 = phi i1 [ true, %or.end.703 ], [ %t2155, %or.rhs.704 ], !dbg !326
  br i1 %t2156, label %or.end.707, label %or.rhs.706, !dbg !326
or.rhs.706:
  %t2157 = load i32, ptr %slot2148, !dbg !326
  %t2158 = icmp eq i32 %t2157, 13, !dbg !326
  br label %or.end.707, !dbg !326
or.end.707:
  %t2159 = phi i1 [ true, %or.end.705 ], [ %t2158, %or.rhs.706 ], !dbg !326
  br i1 %t2159, label %if.then.708, label %if.else.709, !dbg !326
if.then.708:
  %t2160 = load i32, ptr %slot1629, !dbg !327
  %t2161 = add i32 %t2160, 1, !dbg !327
  store i32 %t2161, ptr %slot1629, !dbg !327
  br label %if.end.701, !dbg !327
if.else.709:
  store i1 false, ptr %slot2137, !dbg !328
  br label %if.end.701, !dbg !328
if.end.701:
  br label %while.head.696, !dbg !328
while.end.698:
  br label %if.end.687, !dbg !328
if.else.689:
  br label %if.end.687, !dbg !328
if.end.687:
  %t2162 = load i32, ptr %slot1629, !dbg !329
  %t2163 = load i32, ptr %slot20, !dbg !329
  %t2164 = icmp uge i32 %t2162, %t2163, !dbg !329
  br i1 %t2164, label %or.end.712, label %or.rhs.711, !dbg !329
or.rhs.711:
  %t2165 = load i32, ptr %slot1629, !dbg !329
  %t2166 = zext i32 %t2165 to i64, !dbg !329
  %t2167 = icmp uge i64 %t2166, %t15, !dbg !329
  br i1 %t2167, label %lua.raise.713, label %lua.ok.714, !prof !7, !dbg !329
lua.raise.713:
  %t2168 = getelementptr inbounds ptr, ptr %t1, i64 11, !dbg !329
  %rt.raise.2169 = load ptr, ptr %t2168, !invariant.load !8, !dbg !329
  call void %rt.raise.2169(ptr %L, i64 3) nomerge, !dbg !329
  unreachable, !dbg !329
lua.ok.714:
  %t2170 = getelementptr inbounds i8, ptr %t14, i64 %t2166, !dbg !329
  %t2171 = load i8, ptr %t2170, !dbg !329
  %t2172 = zext i8 %t2171 to i32, !dbg !329
  %t2173 = icmp ne i32 %t2172, 34, !dbg !329
  br label %or.end.712, !dbg !329
or.end.712:
  %t2174 = phi i1 [ true, %if.end.687 ], [ %t2173, %lua.ok.714 ], !dbg !329
  br i1 %t2174, label %if.then.715, label %if.else.716, !dbg !329
if.then.715:
  call void @lua_pushvalue(ptr %L, i32 2), !dbg !330
  %t2175 = call i32 @nupp.wrap.u32(double 0x3FF0000000000000), !dbg !330
  %t2176 = uitofp i32 %t2175 to double, !dbg !330
  call void @lua_pushnumber(ptr %L, double %t2176), !dbg !330
  %t2177 = load i32, ptr %slot1629, !dbg !330
  %t2178 = add i32 %t2177, 1, !dbg !330
  %t2179 = uitofp i32 %t2178 to double, !dbg !330
  call void @lua_pushnumber(ptr %L, double %t2179), !dbg !330
  ret i32 3, !dbg !330
if.else.716:
  br label %if.end.710, !dbg !330
if.end.710:
  %t2180 = load i32, ptr %slot1629, !dbg !331
  store i32 %t2180, ptr %slot2181, !dbg !331
  %t2182 = load i32, ptr %slot1633, !dbg !332
  %t2183 = load i32, ptr %slot35, !dbg !332
  %t2184 = icmp uge i32 %t2182, %t2183, !dbg !332
  br i1 %t2184, label %or.end.719, label %or.rhs.718, !dbg !332
or.rhs.718:
  %t2185 = load i32, ptr %slot1633, !dbg !332
  %t2186 = getelementptr inbounds { ptr, i32, i32, i32, i32, [32 x i32] }, ptr %slot27, i32 0, i32 0, !dbg !332
  %t2187 = load ptr, ptr %t2186, !dbg !332
  %t2188 = zext i32 %t2185 to i64, !dbg !332
  %t2189 = getelementptr inbounds i32, ptr %t2187, i64 %t2188, !dbg !332
  %t2190 = load i32, ptr %t2189, !dbg !332
  %t2191 = load i32, ptr %slot2181, !dbg !332
  %t2192 = icmp ne i32 %t2190, %t2191, !dbg !332
  br label %or.end.719, !dbg !332
or.end.719:
  %t2193 = phi i1 [ true, %if.end.710 ], [ %t2192, %or.rhs.718 ], !dbg !332
  br i1 %t2193, label %if.then.720, label %if.else.721, !dbg !332
if.then.720:
  call void @lua_pushvalue(ptr %L, i32 2), !dbg !333
  %t2194 = call i32 @nupp.wrap.u32(double 0x4014000000000000), !dbg !333
  %t2195 = uitofp i32 %t2194 to double, !dbg !333
  call void @lua_pushnumber(ptr %L, double %t2195), !dbg !333
  %t2196 = load i32, ptr %slot1629, !dbg !333
  %t2197 = add i32 %t2196, 1, !dbg !333
  %t2198 = uitofp i32 %t2197 to double, !dbg !333
  call void @lua_pushnumber(ptr %L, double %t2198), !dbg !333
  ret i32 3, !dbg !333
if.else.721:
  br label %if.end.717, !dbg !333
if.end.717:
  %t2199 = load i32, ptr %slot1633, !dbg !334
  %t2200 = add i32 %t2199, 1, !dbg !334
  store i32 %t2200, ptr %slot1633, !dbg !334
  %t2201 = load i32, ptr %slot1633, !dbg !335
  %t2202 = load i32, ptr %slot35, !dbg !335
  %t2203 = icmp uge i32 %t2201, %t2202, !dbg !335
  br i1 %t2203, label %if.then.723, label %if.else.724, !dbg !335
if.then.723:
  call void @lua_pushvalue(ptr %L, i32 2), !dbg !336
  %t2204 = call i32 @nupp.wrap.u32(double 0x3FF0000000000000), !dbg !336
  %t2205 = uitofp i32 %t2204 to double, !dbg !336
  call void @lua_pushnumber(ptr %L, double %t2205), !dbg !336
  %t2206 = load i32, ptr %slot1629, !dbg !336
  %t2207 = add i32 %t2206, 1, !dbg !336
  %t2208 = uitofp i32 %t2207 to double, !dbg !336
  call void @lua_pushnumber(ptr %L, double %t2208), !dbg !336
  ret i32 3, !dbg !336
if.else.724:
  br label %if.end.722, !dbg !336
if.end.722:
  %t2209 = load i32, ptr %slot1633, !dbg !337
  %t2210 = getelementptr inbounds { ptr, i32, i32, i32, i32, [32 x i32] }, ptr %slot27, i32 0, i32 2, !dbg !337
  %t2211 = load i32, ptr %t2210, !dbg !337
  %t2212 = icmp uge i32 %t2209, %t2211, !dbg !337
  br i1 %t2212, label %lua.raise.725, label %lua.ok.726, !prof !7, !dbg !337
lua.raise.725:
  %t2213 = getelementptr inbounds ptr, ptr %t1, i64 11, !dbg !337
  %rt.raise.2214 = load ptr, ptr %t2213, !invariant.load !8, !dbg !337
  call void %rt.raise.2214(ptr %L, i64 7) nomerge, !dbg !337
  unreachable, !dbg !337
lua.ok.726:
  %t2215 = getelementptr inbounds { ptr, i32, i32, i32, i32, [32 x i32] }, ptr %slot27, i32 0, i32 0, !dbg !337
  %t2216 = load ptr, ptr %t2215, !dbg !337
  %t2217 = zext i32 %t2209 to i64, !dbg !337
  %t2218 = getelementptr inbounds i32, ptr %t2216, i64 %t2217, !dbg !337
  %t2219 = load i32, ptr %t2218, !dbg !337
  store i32 %t2219, ptr %slot2220, !dbg !337
  %t2221 = load i32, ptr %slot2220, !dbg !338
  %t2222 = and i32 %t2221, 2147483647, !dbg !338
  store i32 %t2222, ptr %slot2223, !dbg !338
  %t2224 = load i32, ptr %slot2220, !dbg !339
  %t2225 = and i32 %t2224, 2147483648, !dbg !339
  %t2226 = icmp ne i32 %t2225, 0, !dbg !339
  store i1 %t2226, ptr %slot2227, !dbg !339
  %t2228 = load i32, ptr %slot1633, !dbg !340
  %t2229 = add i32 %t2228, 1, !dbg !340
  store i32 %t2229, ptr %slot1633, !dbg !340
  %t2230 = load i32, ptr %slot2181, !dbg !341
  %t2231 = add i32 %t2230, 1, !dbg !341
  store i32 %t2231, ptr %slot2232, !dbg !341
  %t2233 = load i32, ptr %slot2223, !dbg !342
  %t2234 = load i32, ptr %slot2232, !dbg !342
  %t2235 = sub i32 %t2233, %t2234, !dbg !342
  store i32 %t2235, ptr %slot2236, !dbg !342
  %t2237 = load i32, ptr %slot2232, !dbg !343
  %t2238 = zext i32 %t2237 to i64, !dbg !343
  %t2239 = load i32, ptr %slot2236, !dbg !343
  %t2240 = zext i32 %t2239 to i64, !dbg !343
  %t2241 = load i1, ptr %slot2227, !dbg !343
  %t2242 = zext i1 %t2241 to i64, !dbg !343
  %t2243 = getelementptr inbounds ptr, ptr %t1, i64 49, !dbg !343
  %rt.builder_string.2244 = load ptr, ptr %t2243, !invariant.load !8, !dbg !343
  call void %rt.builder_string.2244(ptr %L, ptr %slot1618, ptr %t14, i64 %t15, i64 %t2238, i64 %t2240, i64 %t2242, i64 1, i64 1), !dbg !343
  %t2245 = load i32, ptr %slot2223, !dbg !344
  %t2246 = add i32 %t2245, 1, !dbg !344
  store i32 %t2246, ptr %slot1629, !dbg !344
  store i1 true, ptr %slot2247, !dbg !345
  br label %while.head.727, !dbg !346
while.head.727:
  %t2248 = load i1, ptr %slot2247, !dbg !346
  br i1 %t2248, label %and.rhs.730, label %and.end.731, !dbg !346
and.rhs.730:
  %t2249 = load i32, ptr %slot1629, !dbg !346
  %t2250 = load i32, ptr %slot20, !dbg !346
  %t2251 = icmp ult i32 %t2249, %t2250, !dbg !346
  br label %and.end.731, !dbg !346
and.end.731:
  %t2252 = phi i1 [ false, %while.head.727 ], [ %t2251, %and.rhs.730 ], !dbg !346
  br i1 %t2252, label %while.body.728, label %while.end.729, !dbg !346
while.body.728:
  %t2253 = load i32, ptr %slot1629, !dbg !347
  %t2254 = zext i32 %t2253 to i64, !dbg !347
  %t2255 = getelementptr inbounds i8, ptr %t14, i64 %t2254, !dbg !347
  %t2256 = load i8, ptr %t2255, !dbg !347
  %t2257 = zext i8 %t2256 to i32, !dbg !347
  store i32 %t2257, ptr %slot2258, !dbg !347
  %t2259 = load i32, ptr %slot2258, !dbg !348
  %t2260 = icmp eq i32 %t2259, 32, !dbg !348
  br i1 %t2260, label %or.end.734, label %or.rhs.733, !dbg !348
or.rhs.733:
  %t2261 = load i32, ptr %slot2258, !dbg !348
  %t2262 = icmp eq i32 %t2261, 9, !dbg !348
  br label %or.end.734, !dbg !348
or.end.734:
  %t2263 = phi i1 [ true, %while.body.728 ], [ %t2262, %or.rhs.733 ], !dbg !348
  br i1 %t2263, label %or.end.736, label %or.rhs.735, !dbg !348
or.rhs.735:
  %t2264 = load i32, ptr %slot2258, !dbg !348
  %t2265 = icmp eq i32 %t2264, 10, !dbg !348
  br label %or.end.736, !dbg !348
or.end.736:
  %t2266 = phi i1 [ true, %or.end.734 ], [ %t2265, %or.rhs.735 ], !dbg !348
  br i1 %t2266, label %or.end.738, label %or.rhs.737, !dbg !348
or.rhs.737:
  %t2267 = load i32, ptr %slot2258, !dbg !348
  %t2268 = icmp eq i32 %t2267, 13, !dbg !348
  br label %or.end.738, !dbg !348
or.end.738:
  %t2269 = phi i1 [ true, %or.end.736 ], [ %t2268, %or.rhs.737 ], !dbg !348
  br i1 %t2269, label %if.then.739, label %if.else.740, !dbg !348
if.then.739:
  %t2270 = load i32, ptr %slot1629, !dbg !349
  %t2271 = add i32 %t2270, 1, !dbg !349
  store i32 %t2271, ptr %slot1629, !dbg !349
  br label %if.end.732, !dbg !349
if.else.740:
  store i1 false, ptr %slot2247, !dbg !350
  br label %if.end.732, !dbg !350
if.end.732:
  br label %while.head.727, !dbg !350
while.end.729:
  %t2272 = load i32, ptr %slot1629, !dbg !351
  %t2273 = load i32, ptr %slot20, !dbg !351
  %t2274 = icmp uge i32 %t2272, %t2273, !dbg !351
  br i1 %t2274, label %or.end.743, label %or.rhs.742, !dbg !351
or.rhs.742:
  %t2275 = load i32, ptr %slot1629, !dbg !351
  %t2276 = zext i32 %t2275 to i64, !dbg !351
  %t2277 = icmp uge i64 %t2276, %t15, !dbg !351
  br i1 %t2277, label %lua.raise.744, label %lua.ok.745, !prof !7, !dbg !351
lua.raise.744:
  %t2278 = getelementptr inbounds ptr, ptr %t1, i64 11, !dbg !351
  %rt.raise.2279 = load ptr, ptr %t2278, !invariant.load !8, !dbg !351
  call void %rt.raise.2279(ptr %L, i64 3) nomerge, !dbg !351
  unreachable, !dbg !351
lua.ok.745:
  %t2280 = getelementptr inbounds i8, ptr %t14, i64 %t2276, !dbg !351
  %t2281 = load i8, ptr %t2280, !dbg !351
  %t2282 = zext i8 %t2281 to i32, !dbg !351
  %t2283 = icmp ne i32 %t2282, 58, !dbg !351
  br label %or.end.743, !dbg !351
or.end.743:
  %t2284 = phi i1 [ true, %while.end.729 ], [ %t2283, %lua.ok.745 ], !dbg !351
  br i1 %t2284, label %if.then.746, label %if.else.747, !dbg !351
if.then.746:
  call void @lua_pushvalue(ptr %L, i32 2), !dbg !352
  %t2285 = call i32 @nupp.wrap.u32(double 0x3FF0000000000000), !dbg !352
  %t2286 = uitofp i32 %t2285 to double, !dbg !352
  call void @lua_pushnumber(ptr %L, double %t2286), !dbg !352
  %t2287 = load i32, ptr %slot1629, !dbg !352
  %t2288 = add i32 %t2287, 1, !dbg !352
  %t2289 = uitofp i32 %t2288 to double, !dbg !352
  call void @lua_pushnumber(ptr %L, double %t2289), !dbg !352
  ret i32 3, !dbg !352
if.else.747:
  br label %if.end.741, !dbg !352
if.end.741:
  %t2290 = load i32, ptr %slot1633, !dbg !353
  %t2291 = load i32, ptr %slot35, !dbg !353
  %t2292 = icmp uge i32 %t2290, %t2291, !dbg !353
  br i1 %t2292, label %or.end.750, label %or.rhs.749, !dbg !353
or.rhs.749:
  %t2293 = load i32, ptr %slot1633, !dbg !353
  %t2294 = getelementptr inbounds { ptr, i32, i32, i32, i32, [32 x i32] }, ptr %slot27, i32 0, i32 0, !dbg !353
  %t2295 = load ptr, ptr %t2294, !dbg !353
  %t2296 = zext i32 %t2293 to i64, !dbg !353
  %t2297 = getelementptr inbounds i32, ptr %t2295, i64 %t2296, !dbg !353
  %t2298 = load i32, ptr %t2297, !dbg !353
  %t2299 = load i32, ptr %slot1629, !dbg !353
  %t2300 = icmp ne i32 %t2298, %t2299, !dbg !353
  br label %or.end.750, !dbg !353
or.end.750:
  %t2301 = phi i1 [ true, %if.end.741 ], [ %t2300, %or.rhs.749 ], !dbg !353
  br i1 %t2301, label %if.then.751, label %if.else.752, !dbg !353
if.then.751:
  call void @lua_pushvalue(ptr %L, i32 2), !dbg !354
  %t2302 = call i32 @nupp.wrap.u32(double 0x4014000000000000), !dbg !354
  %t2303 = uitofp i32 %t2302 to double, !dbg !354
  call void @lua_pushnumber(ptr %L, double %t2303), !dbg !354
  %t2304 = load i32, ptr %slot1629, !dbg !354
  %t2305 = add i32 %t2304, 1, !dbg !354
  %t2306 = uitofp i32 %t2305 to double, !dbg !354
  call void @lua_pushnumber(ptr %L, double %t2306), !dbg !354
  ret i32 3, !dbg !354
if.else.752:
  br label %if.end.748, !dbg !354
if.end.748:
  %t2307 = load i32, ptr %slot1629, !dbg !355
  %t2308 = add i32 %t2307, 1, !dbg !355
  store i32 %t2308, ptr %slot1629, !dbg !355
  %t2309 = load i32, ptr %slot1633, !dbg !356
  %t2310 = add i32 %t2309, 1, !dbg !356
  store i32 %t2310, ptr %slot1633, !dbg !356
  store i1 true, ptr %slot1634, !dbg !357
  br label %if.end.669, !dbg !357
if.end.669:
  br label %if.end.535, !dbg !357
if.end.535:
  br label %while.head.518, !dbg !357
while.end.520:
  %t2311 = getelementptr inbounds ptr, ptr %t1, i64 65, !dbg !358
  %rt.builder_finish.2312 = load ptr, ptr %t2311, !invariant.load !8, !dbg !358
  call void %rt.builder_finish.2312(ptr %L, ptr %slot1618), !dbg !358
  %t2313 = call i32 @nupp.wrap.u32(double 0x0000000000000000), !dbg !358
  %t2314 = uitofp i32 %t2313 to double, !dbg !358
  call void @lua_pushnumber(ptr %L, double %t2314), !dbg !358
  %t2315 = call i32 @nupp.wrap.u32(double 0x0000000000000000), !dbg !358
  %t2316 = uitofp i32 %t2315 to double, !dbg !358
  call void @lua_pushnumber(ptr %L, double %t2316), !dbg !358
  ret i32 3, !dbg !358
}

define internal <16 x i8> @ks___nupp_const_decode_fused_a640dbc37ebbc1be__5f5f6e757070436f6e73745f6465636f646546757365645f61363430646263333765626263316265_helper_nibble_table(<16 x i8> %h_a_zero, i32 %h_a_e0, i32 %h_a_e1, i32 %h_a_e2, i32 %h_a_e3, i32 %h_a_e4, i32 %h_a_e5, i32 %h_a_e6, i32 %h_a_e7, i32 %h_a_e8, i32 %h_a_e9, i32 %h_a_e10, i32 %h_a_e11, i32 %h_a_e12, i32 %h_a_e13, i32 %h_a_e14, i32 %h_a_e15) #1 {
entry:
  br label %body
body:
  %t1 = trunc i32 %h_a_e0 to i8
  %t2 = insertelement <16 x i8> %h_a_zero, i8 %t1, i32 0
  %t3 = trunc i32 %h_a_e1 to i8
  %t4 = insertelement <16 x i8> %t2, i8 %t3, i32 1
  %t5 = trunc i32 %h_a_e2 to i8
  %t6 = insertelement <16 x i8> %t4, i8 %t5, i32 2
  %t7 = trunc i32 %h_a_e3 to i8
  %t8 = insertelement <16 x i8> %t6, i8 %t7, i32 3
  %t9 = trunc i32 %h_a_e4 to i8
  %t10 = insertelement <16 x i8> %t8, i8 %t9, i32 4
  %t11 = trunc i32 %h_a_e5 to i8
  %t12 = insertelement <16 x i8> %t10, i8 %t11, i32 5
  %t13 = trunc i32 %h_a_e6 to i8
  %t14 = insertelement <16 x i8> %t12, i8 %t13, i32 6
  %t15 = trunc i32 %h_a_e7 to i8
  %t16 = insertelement <16 x i8> %t14, i8 %t15, i32 7
  %t17 = trunc i32 %h_a_e8 to i8
  %t18 = insertelement <16 x i8> %t16, i8 %t17, i32 8
  %t19 = trunc i32 %h_a_e9 to i8
  %t20 = insertelement <16 x i8> %t18, i8 %t19, i32 9
  %t21 = trunc i32 %h_a_e10 to i8
  %t22 = insertelement <16 x i8> %t20, i8 %t21, i32 10
  %t23 = trunc i32 %h_a_e11 to i8
  %t24 = insertelement <16 x i8> %t22, i8 %t23, i32 11
  %t25 = trunc i32 %h_a_e12 to i8
  %t26 = insertelement <16 x i8> %t24, i8 %t25, i32 12
  %t27 = trunc i32 %h_a_e13 to i8
  %t28 = insertelement <16 x i8> %t26, i8 %t27, i32 13
  %t29 = trunc i32 %h_a_e14 to i8
  %t30 = insertelement <16 x i8> %t28, i8 %t29, i32 14
  %t31 = trunc i32 %h_a_e15 to i8
  %t32 = insertelement <16 x i8> %t30, i8 %t31, i32 15
  ret <16 x i8> %t32
}

define internal i32 @ks_db5c9457e129530e___nupp_const_decode_fused_a640dbc37ebbc1be__5f5f6e757070436f6e73745f6465636f646546757365645f61363430646263333765626263316265__neon_lua(ptr %L) #0 !dbg !359 {
entry:
  %slot6 = alloca i64, align 8
  %slot7 = alloca ptr, align 8
  %slot20 = alloca i32, align 4
  %slot27 = alloca { ptr, i32, i32, i32, i32, [32 x i32] }, align 8
  %slot33 = alloca i32, align 4
  %slot35 = alloca i32, align 4
  %slot36 = alloca i1, align 4
  %slot37 = alloca i1, align 4
  %slot38 = alloca i1, align 4
  %slot39 = alloca i1, align 4
  %slot41 = alloca i32, align 4
  %slot43 = alloca i32, align 4
  %slot45 = alloca i32, align 4
  %slot46 = alloca i1, align 4
  %slot48 = alloca i32, align 4
  %slot49 = alloca i1, align 4
  %slot50 = alloca i1, align 4
  %slot55 = alloca i64, align 8
  %slot56 = alloca i1, align 4
  %slot68 = alloca i64, align 8
  %slot70 = alloca i32, align 4
  %slot168 = alloca <16 x i8>
  %slot196 = alloca <16 x i1>
  %slot210 = alloca <16 x i1>
  %slot224 = alloca <16 x i1>
  %slot237 = alloca <16 x i1>
  %slot238 = alloca i1, align 4
  %slot249 = alloca <16 x i1>
  %slot357 = alloca <16 x i8>
  %slot361 = alloca <16 x i8>
  %slot365 = alloca <16 x i8>
  %slot369 = alloca <16 x i8>
  %slot374 = alloca <16 x i8>
  %slot377 = alloca <16 x i8>
  %slot380 = alloca <16 x i8>
  %slot383 = alloca <16 x i8>
  %slot430 = alloca <16 x i8>
  %slot453 = alloca <16 x i8>
  %slot482 = alloca i32, align 4
  %slot483 = alloca i1, align 4
  %slot502 = alloca i32, align 4
  %slot520 = alloca i32, align 4
  %slot562 = alloca i32, align 4
  %slot603 = alloca i32, align 4
  %slot615 = alloca i32, align 4
  %slot624 = alloca i32, align 4
  %slot644 = alloca i1, align 4
  %slot677 = alloca i1, align 4
  %slot752 = alloca i1, align 4
  %slot760 = alloca i32, align 4
  %slot812 = alloca i1, align 4
  %slot1614 = alloca i32, align 4
  %slot1618 = alloca [4096 x i8], align 16
  %slot1632 = alloca i32, align 4
  %slot1636 = alloca i32, align 4
  %slot1637 = alloca i1, align 4
  %slot1638 = alloca i1, align 4
  %slot1640 = alloca i32, align 4
  %slot1643 = alloca i1, align 4
  %slot1678 = alloca i32, align 4
  %slot1680 = alloca i32, align 4
  %slot1682 = alloca i32, align 4
  %slot1684 = alloca i32, align 4
  %slot1686 = alloca i32, align 4
  %slot1688 = alloca i32, align 4
  %slot1701 = alloca i32, align 4
  %slot1726 = alloca i32, align 4
  %slot1729 = alloca i32, align 4
  %slot1794 = alloca i32, align 4
  %slot1800 = alloca i32, align 4
  %slot1809 = alloca i32, align 4
  %slot1811 = alloca i32, align 4
  %slot1812 = alloca i32, align 4
  %slot1845 = alloca i32, align 4
  %slot1851 = alloca i32, align 4
  %slot1860 = alloca i32, align 4
  %slot1862 = alloca i32, align 4
  %slot1863 = alloca i32, align 4
  %slot1899 = alloca i32, align 4
  %slot1905 = alloca i32, align 4
  %slot1914 = alloca i32, align 4
  %slot1916 = alloca i32, align 4
  %slot1917 = alloca i32, align 4
  %slot1960 = alloca i32, align 4
  %slot2036 = alloca i32, align 4
  %slot2053 = alloca i32, align 4
  %slot2055 = alloca i32, align 4
  %slot2058 = alloca i32, align 4
  %slot2062 = alloca i1, align 4
  %slot2074 = alloca i1, align 4
  %slot2140 = alloca i1, align 4
  %slot2151 = alloca i32, align 4
  %slot2184 = alloca i32, align 4
  %slot2223 = alloca i32, align 4
  %slot2226 = alloca i32, align 4
  %slot2230 = alloca i1, align 4
  %slot2235 = alloca i32, align 4
  %slot2239 = alloca i32, align 4
  %slot2250 = alloca i1, align 4
  %slot2261 = alloca i32, align 4
  br label %body
body:
  %t1 = load ptr, ptr @ks.rt, !dbg !360
  %t2 = call i32 @lua_checkstack(ptr %L, i32 10), !dbg !360
  %t3 = icmp eq i32 %t2, 0, !dbg !360
  br i1 %t3, label %lua.raise.1, label %lua.ok.2, !prof !7, !dbg !360
lua.raise.1:
  %t4 = getelementptr inbounds ptr, ptr %t1, i64 11, !dbg !360
  %rt.raise.5 = load ptr, ptr %t4, !invariant.load !8, !dbg !360
  call void %rt.raise.5(ptr %L, i64 1) nomerge, !dbg !360
  unreachable, !dbg !360
lua.ok.2:
  %t8 = call i32 @lua_type(ptr %L, i32 1), !dbg !360
  %t9 = icmp eq i32 %t8, 4, !dbg !360
  br i1 %t9, label %lua.string.3, label %lua.buffer.4, !dbg !360
lua.string.3:
  %t10 = call ptr @luaL_checklstring(ptr %L, i32 1, ptr %slot6), !dbg !360
  store ptr %t10, ptr %slot7, !dbg !360
  br label %lua.bytes.5, !dbg !360
lua.buffer.4:
  %t11 = getelementptr inbounds ptr, ptr %t1, i64 14, !dbg !360
  %rt.bytes.12 = load ptr, ptr %t11, !invariant.load !8, !dbg !360
  %t13 = call ptr %rt.bytes.12(ptr %L, i64 1, ptr %slot6), !dbg !360
  store ptr %t13, ptr %slot7, !dbg !360
  br label %lua.bytes.5, !dbg !360
lua.bytes.5:
  %t14 = load ptr, ptr %slot7, !dbg !360
  %t15 = load i64, ptr %slot6, !dbg !360
  %t16 = icmp ugt i64 %t15, 4294967295, !dbg !361
  br i1 %t16, label %lua.raise.6, label %lua.ok.7, !prof !7, !dbg !361
lua.raise.6:
  %t17 = getelementptr inbounds ptr, ptr %t1, i64 11, !dbg !361
  %rt.raise.18 = load ptr, ptr %t17, !invariant.load !8, !dbg !361
  call void %rt.raise.18(ptr %L, i64 2) nomerge, !dbg !361
  unreachable, !dbg !361
lua.ok.7:
  %t19 = trunc i64 %t15 to i32, !dbg !361
  store i32 %t19, ptr %slot20, !dbg !361
  %t21 = load i32, ptr %slot20, !dbg !362
  %t22 = icmp ult i32 2147483647, %t21, !dbg !362
  br i1 %t22, label %if.then.9, label %if.else.10, !dbg !362
if.then.9:
  call void @lua_pushvalue(ptr %L, i32 2), !dbg !363
  %t23 = call i32 @nupp.wrap.u32(double 0x4014000000000000), !dbg !363
  %t24 = uitofp i32 %t23 to double, !dbg !363
  call void @lua_pushnumber(ptr %L, double %t24), !dbg !363
  %t25 = call i32 @nupp.wrap.u32(double 0x3FF0000000000000), !dbg !363
  %t26 = uitofp i32 %t25 to double, !dbg !363
  call void @lua_pushnumber(ptr %L, double %t26), !dbg !363
  ret i32 3, !dbg !363
if.else.10:
  br label %if.end.8, !dbg !363
if.end.8:
  %t28 = load i32, ptr %slot20, !dbg !364
  %t29 = zext i32 %t28 to i64, !dbg !364
  %t30 = getelementptr inbounds ptr, ptr %t1, i64 29, !dbg !364
  %rt.scratch_u32.31 = load ptr, ptr %t30, !invariant.load !8, !dbg !364
  call void %rt.scratch_u32.31(ptr %L, ptr %slot27, i64 %t29, ptr @ks.key.ks_db5c9457e129530e___nupp_const_decode_fused_a640dbc37ebbc1be__5f5f6e757070436f6e73745f6465636f646546757365645f61363430646263333765626263316265.v2_tape), !dbg !364
  %t32 = call i32 @nupp.wrap.u32(double 0x0000000000000000), !dbg !365
  store i32 %t32, ptr %slot33, !dbg !365
  %t34 = call i32 @nupp.wrap.u32(double 0x0000000000000000), !dbg !366
  store i32 %t34, ptr %slot35, !dbg !366
  store i1 false, ptr %slot36, !dbg !367
  store i1 false, ptr %slot37, !dbg !368
  store i1 false, ptr %slot38, !dbg !369
  store i1 false, ptr %slot39, !dbg !370
  %t40 = call i32 @nupp.wrap.u32(double 0x0000000000000000), !dbg !371
  store i32 %t40, ptr %slot41, !dbg !371
  %t42 = call i32 @nupp.wrap.u32(double 0x0000000000000000), !dbg !372
  store i32 %t42, ptr %slot43, !dbg !372
  %t44 = call i32 @nupp.wrap.u32(double 0x0000000000000000), !dbg !373
  store i32 %t44, ptr %slot45, !dbg !373
  store i1 false, ptr %slot46, !dbg !374
  %t47 = call i32 @nupp.wrap.u32(double 0x0000000000000000), !dbg !375
  store i32 %t47, ptr %slot48, !dbg !375
  store i1 false, ptr %slot49, !dbg !376
  store i1 false, ptr %slot50, !dbg !377
  %t51 = call i64 @llvm.fptosi.sat.i64.f64(double 0x3FF0000000000000), !dbg !378
  %t52 = call i64 @llvm.fptoui.sat.i64.f64(double 0x3FF0000000000000), !dbg !378
  %t53 = fcmp olt double 0x3FF0000000000000, 0.0, !dbg !378
  %t54 = select i1 %t53, i64 %t51, i64 %t52, !dbg !378
  store i64 %t54, ptr %slot55, !dbg !378
  store i1 false, ptr %slot56, !dbg !379
  %t57 = icmp ule i64 %t15, 4294967295, !dbg !380
  br i1 %t57, label %cursors.wide.11, label %cursors.narrow.12, !dbg !380
cursors.wide.11:
  br label %while.head.14, !dbg !380
while.head.14:
  %t58 = load i32, ptr %slot33, !dbg !380
  %t59 = load i32, ptr %slot20, !dbg !380
  %t60 = icmp ult i32 %t58, %t59, !dbg !380
  br i1 %t60, label %or.end.18, label %or.rhs.17, !dbg !380
or.rhs.17:
  %t61 = load i1, ptr %slot49, !dbg !380
  %t62 = xor i1 %t61, true, !dbg !380
  br label %or.end.18, !dbg !380
or.end.18:
  %t63 = phi i1 [ true, %while.head.14 ], [ %t62, %or.rhs.17 ], !dbg !380
  br i1 %t63, label %while.body.15, label %while.end.16, !dbg !380
while.body.15:
  %t64 = call i64 @llvm.fptosi.sat.i64.f64(double 0x0000000000000000), !dbg !381
  %t65 = call i64 @llvm.fptoui.sat.i64.f64(double 0x0000000000000000), !dbg !381
  %t66 = fcmp olt double 0x0000000000000000, 0.0, !dbg !381
  %t67 = select i1 %t66, i64 %t64, i64 %t65, !dbg !381
  store i64 %t67, ptr %slot68, !dbg !381
  %t69 = call i32 @nupp.wrap.u32(double 0x0000000000000000), !dbg !382
  store i32 %t69, ptr %slot70, !dbg !382
  br i1 true, label %if.then.20, label %if.else.21, !dbg !383
if.then.20:
  %t71 = load i1, ptr %slot56, !dbg !384
  %t72 = xor i1 %t71, true, !dbg !384
  br i1 %t72, label %and.rhs.23, label %and.end.24, !dbg !384
and.rhs.23:
  %t73 = load i32, ptr %slot33, !dbg !384
  %t74 = zext i32 %t73 to i64, !dbg !384
  %t75 = zext i32 16 to i64, !dbg !384
  %t76 = add i64 %t74, %t75, !dbg !384
  %t77 = load i32, ptr %slot20, !dbg !384
  %t78 = zext i32 %t77 to i64, !dbg !384
  %t79 = icmp ule i64 %t76, %t78, !dbg !384
  br label %and.end.24, !dbg !384
and.end.24:
  %t80 = phi i1 [ false, %if.then.20 ], [ %t79, %and.rhs.23 ], !dbg !384
  br i1 %t80, label %if.then.25, label %if.else.26, !dbg !384
if.then.25:
  %t81 = load i32, ptr %slot33, !dbg !385
  %t82 = zext i32 %t81 to i64, !dbg !385
  %t83 = add nuw i64 %t82, 0, !dbg !385
  %t84 = getelementptr inbounds nuw i8, ptr %t14, i64 %t83, !dbg !385
  br i1 true, label %simd.yes.27, label %simd.no.28, !dbg !385
simd.yes.27:
  %t85 = load <16 x i8>, ptr %t84, align 1, !dbg !385
  br label %simd.join.29, !dbg !385
simd.no.28:
  %t86 = load i32, ptr %slot33, !dbg !385
  %t87 = add i32 %t86, 1, !dbg !385
  %t88 = zext i32 %t87 to i64, !dbg !385
  %t89 = icmp ne i64 %t88, 0, !dbg !385
  %t90 = sub i64 %t88, 1, !dbg !385
  %t91 = select i1 %t89, i64 %t90, i64 -1, !dbg !385
  %t92 = icmp ult i64 %t91, %t15, !dbg !385
  %t93 = sub i64 %t15, %t91, !dbg !385
  %t94 = icmp ult i64 %t93, 16, !dbg !385
  %t95 = select i1 %t94, i64 %t93, i64 16, !dbg !385
  %t96 = select i1 %t92, i64 %t95, i64 0, !dbg !385
  %t97 = trunc i64 %t96 to i32, !dbg !385
  %t98 = select i1 %t92, i64 %t91, i64 0, !dbg !385
  %t99 = getelementptr inbounds i8, ptr %t14, i64 %t98, !dbg !385
  %t100 = icmp eq i32 %t97, 16, !dbg !385
  br i1 %t100, label %simd.yes.30, label %simd.no.31, !dbg !385
simd.yes.30:
  %t101 = load <16 x i8>, ptr %t99, align 1, !dbg !385
  br label %simd.join.32, !dbg !385
simd.no.31:
  switch i32 %t97, label %tail.done.49 [ i32 1, label %tail.lane.33 i32 2, label %tail.lane.34 i32 3, label %tail.lane.35 i32 4, label %tail.lane.36 i32 5, label %tail.lane.37 i32 6, label %tail.lane.38 i32 7, label %tail.lane.39 i32 8, label %tail.lane.40 i32 9, label %tail.lane.41 i32 10, label %tail.lane.42 i32 11, label %tail.lane.43 i32 12, label %tail.lane.44 i32 13, label %tail.lane.45 i32 14, label %tail.lane.46 i32 15, label %tail.lane.47 i32 16, label %tail.lane.48 ], !dbg !385
tail.lane.48:
  %t102 = getelementptr inbounds i8, ptr %t99, i64 15, !dbg !385
  %t103 = load i8, ptr %t102, align 1, !dbg !385
  %t104 = insertelement <16 x i8> zeroinitializer, i8 %t103, i32 15, !dbg !385
  br label %tail.lane.47, !dbg !385
tail.lane.47:
  %t105 = phi <16 x i8> [ zeroinitializer, %simd.no.31 ], [ %t104, %tail.lane.48 ], !dbg !385
  %t106 = getelementptr inbounds i8, ptr %t99, i64 14, !dbg !385
  %t107 = load i8, ptr %t106, align 1, !dbg !385
  %t108 = insertelement <16 x i8> %t105, i8 %t107, i32 14, !dbg !385
  br label %tail.lane.46, !dbg !385
tail.lane.46:
  %t109 = phi <16 x i8> [ zeroinitializer, %simd.no.31 ], [ %t108, %tail.lane.47 ], !dbg !385
  %t110 = getelementptr inbounds i8, ptr %t99, i64 13, !dbg !385
  %t111 = load i8, ptr %t110, align 1, !dbg !385
  %t112 = insertelement <16 x i8> %t109, i8 %t111, i32 13, !dbg !385
  br label %tail.lane.45, !dbg !385
tail.lane.45:
  %t113 = phi <16 x i8> [ zeroinitializer, %simd.no.31 ], [ %t112, %tail.lane.46 ], !dbg !385
  %t114 = getelementptr inbounds i8, ptr %t99, i64 12, !dbg !385
  %t115 = load i8, ptr %t114, align 1, !dbg !385
  %t116 = insertelement <16 x i8> %t113, i8 %t115, i32 12, !dbg !385
  br label %tail.lane.44, !dbg !385
tail.lane.44:
  %t117 = phi <16 x i8> [ zeroinitializer, %simd.no.31 ], [ %t116, %tail.lane.45 ], !dbg !385
  %t118 = getelementptr inbounds i8, ptr %t99, i64 11, !dbg !385
  %t119 = load i8, ptr %t118, align 1, !dbg !385
  %t120 = insertelement <16 x i8> %t117, i8 %t119, i32 11, !dbg !385
  br label %tail.lane.43, !dbg !385
tail.lane.43:
  %t121 = phi <16 x i8> [ zeroinitializer, %simd.no.31 ], [ %t120, %tail.lane.44 ], !dbg !385
  %t122 = getelementptr inbounds i8, ptr %t99, i64 10, !dbg !385
  %t123 = load i8, ptr %t122, align 1, !dbg !385
  %t124 = insertelement <16 x i8> %t121, i8 %t123, i32 10, !dbg !385
  br label %tail.lane.42, !dbg !385
tail.lane.42:
  %t125 = phi <16 x i8> [ zeroinitializer, %simd.no.31 ], [ %t124, %tail.lane.43 ], !dbg !385
  %t126 = getelementptr inbounds i8, ptr %t99, i64 9, !dbg !385
  %t127 = load i8, ptr %t126, align 1, !dbg !385
  %t128 = insertelement <16 x i8> %t125, i8 %t127, i32 9, !dbg !385
  br label %tail.lane.41, !dbg !385
tail.lane.41:
  %t129 = phi <16 x i8> [ zeroinitializer, %simd.no.31 ], [ %t128, %tail.lane.42 ], !dbg !385
  %t130 = getelementptr inbounds i8, ptr %t99, i64 8, !dbg !385
  %t131 = load i8, ptr %t130, align 1, !dbg !385
  %t132 = insertelement <16 x i8> %t129, i8 %t131, i32 8, !dbg !385
  br label %tail.lane.40, !dbg !385
tail.lane.40:
  %t133 = phi <16 x i8> [ zeroinitializer, %simd.no.31 ], [ %t132, %tail.lane.41 ], !dbg !385
  %t134 = getelementptr inbounds i8, ptr %t99, i64 7, !dbg !385
  %t135 = load i8, ptr %t134, align 1, !dbg !385
  %t136 = insertelement <16 x i8> %t133, i8 %t135, i32 7, !dbg !385
  br label %tail.lane.39, !dbg !385
tail.lane.39:
  %t137 = phi <16 x i8> [ zeroinitializer, %simd.no.31 ], [ %t136, %tail.lane.40 ], !dbg !385
  %t138 = getelementptr inbounds i8, ptr %t99, i64 6, !dbg !385
  %t139 = load i8, ptr %t138, align 1, !dbg !385
  %t140 = insertelement <16 x i8> %t137, i8 %t139, i32 6, !dbg !385
  br label %tail.lane.38, !dbg !385
tail.lane.38:
  %t141 = phi <16 x i8> [ zeroinitializer, %simd.no.31 ], [ %t140, %tail.lane.39 ], !dbg !385
  %t142 = getelementptr inbounds i8, ptr %t99, i64 5, !dbg !385
  %t143 = load i8, ptr %t142, align 1, !dbg !385
  %t144 = insertelement <16 x i8> %t141, i8 %t143, i32 5, !dbg !385
  br label %tail.lane.37, !dbg !385
tail.lane.37:
  %t145 = phi <16 x i8> [ zeroinitializer, %simd.no.31 ], [ %t144, %tail.lane.38 ], !dbg !385
  %t146 = getelementptr inbounds i8, ptr %t99, i64 4, !dbg !385
  %t147 = load i8, ptr %t146, align 1, !dbg !385
  %t148 = insertelement <16 x i8> %t145, i8 %t147, i32 4, !dbg !385
  br label %tail.lane.36, !dbg !385
tail.lane.36:
  %t149 = phi <16 x i8> [ zeroinitializer, %simd.no.31 ], [ %t148, %tail.lane.37 ], !dbg !385
  %t150 = getelementptr inbounds i8, ptr %t99, i64 3, !dbg !385
  %t151 = load i8, ptr %t150, align 1, !dbg !385
  %t152 = insertelement <16 x i8> %t149, i8 %t151, i32 3, !dbg !385
  br label %tail.lane.35, !dbg !385
tail.lane.35:
  %t153 = phi <16 x i8> [ zeroinitializer, %simd.no.31 ], [ %t152, %tail.lane.36 ], !dbg !385
  %t154 = getelementptr inbounds i8, ptr %t99, i64 2, !dbg !385
  %t155 = load i8, ptr %t154, align 1, !dbg !385
  %t156 = insertelement <16 x i8> %t153, i8 %t155, i32 2, !dbg !385
  br label %tail.lane.34, !dbg !385
tail.lane.34:
  %t157 = phi <16 x i8> [ zeroinitializer, %simd.no.31 ], [ %t156, %tail.lane.35 ], !dbg !385
  %t158 = getelementptr inbounds i8, ptr %t99, i64 1, !dbg !385
  %t159 = load i8, ptr %t158, align 1, !dbg !385
  %t160 = insertelement <16 x i8> %t157, i8 %t159, i32 1, !dbg !385
  br label %tail.lane.33, !dbg !385
tail.lane.33:
  %t161 = phi <16 x i8> [ zeroinitializer, %simd.no.31 ], [ %t160, %tail.lane.34 ], !dbg !385
  %t162 = getelementptr inbounds i8, ptr %t99, i64 0, !dbg !385
  %t163 = load i8, ptr %t162, align 1, !dbg !385
  %t164 = insertelement <16 x i8> %t161, i8 %t163, i32 0, !dbg !385
  br label %tail.done.49, !dbg !385
tail.done.49:
  %t165 = phi <16 x i8> [ zeroinitializer, %simd.no.31 ], [ %t164, %tail.lane.33 ], !dbg !385
  br label %simd.join.32, !dbg !385
simd.join.32:
  %t166 = phi <16 x i8> [ %t101, %simd.yes.30 ], [ %t165, %tail.done.49 ], !dbg !385
  br label %simd.join.29, !dbg !385
simd.join.29:
  %t167 = phi <16 x i8> [ %t85, %simd.yes.27 ], [ %t166, %simd.join.32 ], !dbg !385
  store <16 x i8> %t167, ptr %slot168, !dbg !385
  %t169 = load <16 x i8>, ptr %slot168, !dbg !386
  %t170 = call i32 @nupp.wrap.u32(double 0x405EC00000000000), !dbg !386
  %t171 = trunc i32 %t170 to i8, !dbg !386
  %t172 = insertelement <16 x i8> poison, i8 %t171, i64 0, !dbg !386
  %t173 = shufflevector <16 x i8> %t172, <16 x i8> poison, <16 x i32> zeroinitializer, !dbg !386
  %t174 = icmp eq <16 x i8> %t169, %t173, !dbg !386
  %t175 = load <16 x i8>, ptr %slot168, !dbg !386
  %t176 = call i32 @nupp.wrap.u32(double 0x405F400000000000), !dbg !386
  %t177 = trunc i32 %t176 to i8, !dbg !386
  %t178 = insertelement <16 x i8> poison, i8 %t177, i64 0, !dbg !386
  %t179 = shufflevector <16 x i8> %t178, <16 x i8> poison, <16 x i32> zeroinitializer, !dbg !386
  %t180 = icmp eq <16 x i8> %t175, %t179, !dbg !386
  %t181 = or <16 x i1> %t174, %t180, !dbg !386
  %t182 = load <16 x i8>, ptr %slot168, !dbg !386
  %t183 = call i32 @nupp.wrap.u32(double 0x4056C00000000000), !dbg !386
  %t184 = trunc i32 %t183 to i8, !dbg !386
  %t185 = insertelement <16 x i8> poison, i8 %t184, i64 0, !dbg !386
  %t186 = shufflevector <16 x i8> %t185, <16 x i8> poison, <16 x i32> zeroinitializer, !dbg !386
  %t187 = icmp eq <16 x i8> %t182, %t186, !dbg !386
  %t188 = or <16 x i1> %t181, %t187, !dbg !386
  %t189 = load <16 x i8>, ptr %slot168, !dbg !386
  %t190 = call i32 @nupp.wrap.u32(double 0x4057400000000000), !dbg !386
  %t191 = trunc i32 %t190 to i8, !dbg !386
  %t192 = insertelement <16 x i8> poison, i8 %t191, i64 0, !dbg !386
  %t193 = shufflevector <16 x i8> %t192, <16 x i8> poison, <16 x i32> zeroinitializer, !dbg !386
  %t194 = icmp eq <16 x i8> %t189, %t193, !dbg !386
  %t195 = or <16 x i1> %t188, %t194, !dbg !386
  store <16 x i1> %t195, ptr %slot196, !dbg !386
  %t197 = load <16 x i8>, ptr %slot168, !dbg !387
  %t198 = call i32 @nupp.wrap.u32(double 0x404D000000000000), !dbg !387
  %t199 = trunc i32 %t198 to i8, !dbg !387
  %t200 = insertelement <16 x i8> poison, i8 %t199, i64 0, !dbg !387
  %t201 = shufflevector <16 x i8> %t200, <16 x i8> poison, <16 x i32> zeroinitializer, !dbg !387
  %t202 = icmp eq <16 x i8> %t197, %t201, !dbg !387
  %t203 = load <16 x i8>, ptr %slot168, !dbg !387
  %t204 = call i32 @nupp.wrap.u32(double 0x4046000000000000), !dbg !387
  %t205 = trunc i32 %t204 to i8, !dbg !387
  %t206 = insertelement <16 x i8> poison, i8 %t205, i64 0, !dbg !387
  %t207 = shufflevector <16 x i8> %t206, <16 x i8> poison, <16 x i32> zeroinitializer, !dbg !387
  %t208 = icmp eq <16 x i8> %t203, %t207, !dbg !387
  %t209 = or <16 x i1> %t202, %t208, !dbg !387
  store <16 x i1> %t209, ptr %slot210, !dbg !387
  %t211 = load <16 x i8>, ptr %slot168, !dbg !388
  %t212 = call i32 @nupp.wrap.u32(double 0x4041000000000000), !dbg !388
  %t213 = trunc i32 %t212 to i8, !dbg !388
  %t214 = insertelement <16 x i8> poison, i8 %t213, i64 0, !dbg !388
  %t215 = shufflevector <16 x i8> %t214, <16 x i8> poison, <16 x i32> zeroinitializer, !dbg !388
  %t216 = icmp eq <16 x i8> %t211, %t215, !dbg !388
  %t217 = load <16 x i8>, ptr %slot168, !dbg !388
  %t218 = call i32 @nupp.wrap.u32(double 0x4057000000000000), !dbg !388
  %t219 = trunc i32 %t218 to i8, !dbg !388
  %t220 = insertelement <16 x i8> poison, i8 %t219, i64 0, !dbg !388
  %t221 = shufflevector <16 x i8> %t220, <16 x i8> poison, <16 x i32> zeroinitializer, !dbg !388
  %t222 = icmp eq <16 x i8> %t217, %t221, !dbg !388
  %t223 = or <16 x i1> %t216, %t222, !dbg !388
  store <16 x i1> %t223, ptr %slot224, !dbg !388
  %t225 = load <16 x i1>, ptr %slot196, !dbg !389
  %t226 = load <16 x i1>, ptr %slot210, !dbg !389
  %t227 = or <16 x i1> %t225, %t226, !dbg !389
  %t228 = load <16 x i1>, ptr %slot224, !dbg !389
  %t229 = or <16 x i1> %t227, %t228, !dbg !389
  %t230 = load <16 x i8>, ptr %slot168, !dbg !389
  %t231 = call i32 @nupp.wrap.u32(double 0x4040000000000000), !dbg !389
  %t232 = trunc i32 %t231 to i8, !dbg !389
  %t233 = insertelement <16 x i8> poison, i8 %t232, i64 0, !dbg !389
  %t234 = shufflevector <16 x i8> %t233, <16 x i8> poison, <16 x i32> zeroinitializer, !dbg !389
  %t235 = icmp ult <16 x i8> %t230, %t234, !dbg !389
  %t236 = or <16 x i1> %t229, %t235, !dbg !389
  store <16 x i1> %t236, ptr %slot237, !dbg !389
  store i1 false, ptr %slot238, !dbg !390
  %t239 = load i1, ptr %slot50, !dbg !391
  br i1 %t239, label %if.then.51, label %if.else.52, !dbg !391
if.then.51:
  %t240 = load <16 x i1>, ptr %slot237, !dbg !392
  %t241 = bitcast <16 x i1> %t240 to i16, !dbg !392
  %t242 = zext i16 %t241 to i64, !dbg !392
  store i64 %t242, ptr %slot68, !dbg !392
  store i1 true, ptr %slot238, !dbg !393
  br label %if.end.50, !dbg !393
if.else.52:
  %t243 = load <16 x i8>, ptr %slot168, !dbg !394
  %t244 = call i32 @nupp.wrap.u32(double 0x4060000000000000), !dbg !394
  %t245 = trunc i32 %t244 to i8, !dbg !394
  %t246 = insertelement <16 x i8> poison, i8 %t245, i64 0, !dbg !394
  %t247 = shufflevector <16 x i8> %t246, <16 x i8> poison, <16 x i32> zeroinitializer, !dbg !394
  %t248 = icmp uge <16 x i8> %t243, %t247, !dbg !394
  store <16 x i1> %t248, ptr %slot249, !dbg !394
  %t250 = load <16 x i1>, ptr %slot237, !dbg !395
  %t251 = load <16 x i1>, ptr %slot249, !dbg !395
  %t252 = or <16 x i1> %t250, %t251, !dbg !395
  %t253 = bitcast <16 x i1> %t252 to i16, !dbg !395
  %t254 = zext i16 %t253 to i64, !dbg !395
  store i64 %t254, ptr %slot68, !dbg !395
  %t255 = load i64, ptr %slot68, !dbg !396
  %t256 = call i64 @llvm.fptosi.sat.i64.f64(double 0x0000000000000000), !dbg !396
  %t257 = call i64 @llvm.fptoui.sat.i64.f64(double 0x0000000000000000), !dbg !396
  %t258 = fcmp olt double 0x0000000000000000, 0.0, !dbg !396
  %t259 = select i1 %t258, i64 %t256, i64 %t257, !dbg !396
  %t260 = icmp ne i64 %t255, %t259, !dbg !396
  br i1 %t260, label %if.then.54, label %if.else.55, !dbg !396
if.then.54:
  %t261 = load <16 x i1>, ptr %slot249, !dbg !397
  %t262 = sext <16 x i1> %t261 to <16 x i8>, !dbg !397
  %t263 = call <16 x i8> asm "", "=w,0"(<16 x i8> %t262), !dbg !397
  %t264 = bitcast <16 x i8> %t263 to <4 x i32>, !dbg !397
  %t265 = shufflevector <4 x i32> %t264, <4 x i32> poison, <4 x i32> <i32 0, i32 1, i32 2, i32 3>, !dbg !397
  %t266 = call <4 x i32> @llvm.aarch64.neon.umaxp.v4i32(<4 x i32> %t265, <4 x i32> %t265), !dbg !397
  %t267 = bitcast <4 x i32> %t266 to <2 x i64>, !dbg !397
  %t268 = extractelement <2 x i64> %t267, i32 0, !dbg !397
  %t269 = icmp ne i64 %t268, 0, !dbg !397
  store i1 %t269, ptr %slot238, !dbg !397
  %t270 = load i1, ptr %slot238, !dbg !398
  br i1 %t270, label %if.then.57, label %if.else.58, !dbg !398
if.then.57:
  %t271 = load <16 x i1>, ptr %slot237, !dbg !399
  %t272 = bitcast <16 x i1> %t271 to i16, !dbg !399
  %t273 = zext i16 %t272 to i64, !dbg !399
  store i64 %t273, ptr %slot68, !dbg !399
  br label %if.end.56, !dbg !399
if.else.58:
  br label %if.end.56, !dbg !399
if.end.56:
  br label %if.end.53, !dbg !399
if.else.55:
  br label %if.end.53, !dbg !399
if.end.53:
  br label %if.end.50, !dbg !399
if.end.50:
  %t274 = load i1, ptr %slot238, !dbg !400
  br i1 %t274, label %if.then.60, label %if.else.61, !dbg !400
if.then.60:
  %t275 = load i32, ptr %slot33, !dbg !401
  %t276 = sub i32 %t275, 16, !dbg !401
  %t277 = add i32 %t276, 1, !dbg !401
  %t278 = zext i32 %t277 to i64, !dbg !401
  %t279 = icmp ne i64 %t278, 0, !dbg !401
  %t280 = sub i64 %t278, 1, !dbg !401
  %t281 = select i1 %t279, i64 %t280, i64 -1, !dbg !401
  %t282 = icmp ult i64 %t281, %t15, !dbg !401
  %t283 = sub i64 %t15, %t281, !dbg !401
  %t284 = icmp ult i64 %t283, 16, !dbg !401
  %t285 = select i1 %t284, i64 %t283, i64 16, !dbg !401
  %t286 = select i1 %t282, i64 %t285, i64 0, !dbg !401
  %t287 = trunc i64 %t286 to i32, !dbg !401
  %t288 = select i1 %t282, i64 %t281, i64 0, !dbg !401
  %t289 = getelementptr inbounds i8, ptr %t14, i64 %t288, !dbg !401
  %t290 = icmp eq i32 %t287, 16, !dbg !401
  br i1 %t290, label %simd.yes.62, label %simd.no.63, !dbg !401
simd.yes.62:
  %t291 = load <16 x i8>, ptr %t289, align 1, !dbg !401
  br label %simd.join.64, !dbg !401
simd.no.63:
  switch i32 %t287, label %tail.done.81 [ i32 1, label %tail.lane.65 i32 2, label %tail.lane.66 i32 3, label %tail.lane.67 i32 4, label %tail.lane.68 i32 5, label %tail.lane.69 i32 6, label %tail.lane.70 i32 7, label %tail.lane.71 i32 8, label %tail.lane.72 i32 9, label %tail.lane.73 i32 10, label %tail.lane.74 i32 11, label %tail.lane.75 i32 12, label %tail.lane.76 i32 13, label %tail.lane.77 i32 14, label %tail.lane.78 i32 15, label %tail.lane.79 i32 16, label %tail.lane.80 ], !dbg !401
tail.lane.80:
  %t292 = getelementptr inbounds i8, ptr %t289, i64 15, !dbg !401
  %t293 = load i8, ptr %t292, align 1, !dbg !401
  %t294 = insertelement <16 x i8> zeroinitializer, i8 %t293, i32 15, !dbg !401
  br label %tail.lane.79, !dbg !401
tail.lane.79:
  %t295 = phi <16 x i8> [ zeroinitializer, %simd.no.63 ], [ %t294, %tail.lane.80 ], !dbg !401
  %t296 = getelementptr inbounds i8, ptr %t289, i64 14, !dbg !401
  %t297 = load i8, ptr %t296, align 1, !dbg !401
  %t298 = insertelement <16 x i8> %t295, i8 %t297, i32 14, !dbg !401
  br label %tail.lane.78, !dbg !401
tail.lane.78:
  %t299 = phi <16 x i8> [ zeroinitializer, %simd.no.63 ], [ %t298, %tail.lane.79 ], !dbg !401
  %t300 = getelementptr inbounds i8, ptr %t289, i64 13, !dbg !401
  %t301 = load i8, ptr %t300, align 1, !dbg !401
  %t302 = insertelement <16 x i8> %t299, i8 %t301, i32 13, !dbg !401
  br label %tail.lane.77, !dbg !401
tail.lane.77:
  %t303 = phi <16 x i8> [ zeroinitializer, %simd.no.63 ], [ %t302, %tail.lane.78 ], !dbg !401
  %t304 = getelementptr inbounds i8, ptr %t289, i64 12, !dbg !401
  %t305 = load i8, ptr %t304, align 1, !dbg !401
  %t306 = insertelement <16 x i8> %t303, i8 %t305, i32 12, !dbg !401
  br label %tail.lane.76, !dbg !401
tail.lane.76:
  %t307 = phi <16 x i8> [ zeroinitializer, %simd.no.63 ], [ %t306, %tail.lane.77 ], !dbg !401
  %t308 = getelementptr inbounds i8, ptr %t289, i64 11, !dbg !401
  %t309 = load i8, ptr %t308, align 1, !dbg !401
  %t310 = insertelement <16 x i8> %t307, i8 %t309, i32 11, !dbg !401
  br label %tail.lane.75, !dbg !401
tail.lane.75:
  %t311 = phi <16 x i8> [ zeroinitializer, %simd.no.63 ], [ %t310, %tail.lane.76 ], !dbg !401
  %t312 = getelementptr inbounds i8, ptr %t289, i64 10, !dbg !401
  %t313 = load i8, ptr %t312, align 1, !dbg !401
  %t314 = insertelement <16 x i8> %t311, i8 %t313, i32 10, !dbg !401
  br label %tail.lane.74, !dbg !401
tail.lane.74:
  %t315 = phi <16 x i8> [ zeroinitializer, %simd.no.63 ], [ %t314, %tail.lane.75 ], !dbg !401
  %t316 = getelementptr inbounds i8, ptr %t289, i64 9, !dbg !401
  %t317 = load i8, ptr %t316, align 1, !dbg !401
  %t318 = insertelement <16 x i8> %t315, i8 %t317, i32 9, !dbg !401
  br label %tail.lane.73, !dbg !401
tail.lane.73:
  %t319 = phi <16 x i8> [ zeroinitializer, %simd.no.63 ], [ %t318, %tail.lane.74 ], !dbg !401
  %t320 = getelementptr inbounds i8, ptr %t289, i64 8, !dbg !401
  %t321 = load i8, ptr %t320, align 1, !dbg !401
  %t322 = insertelement <16 x i8> %t319, i8 %t321, i32 8, !dbg !401
  br label %tail.lane.72, !dbg !401
tail.lane.72:
  %t323 = phi <16 x i8> [ zeroinitializer, %simd.no.63 ], [ %t322, %tail.lane.73 ], !dbg !401
  %t324 = getelementptr inbounds i8, ptr %t289, i64 7, !dbg !401
  %t325 = load i8, ptr %t324, align 1, !dbg !401
  %t326 = insertelement <16 x i8> %t323, i8 %t325, i32 7, !dbg !401
  br label %tail.lane.71, !dbg !401
tail.lane.71:
  %t327 = phi <16 x i8> [ zeroinitializer, %simd.no.63 ], [ %t326, %tail.lane.72 ], !dbg !401
  %t328 = getelementptr inbounds i8, ptr %t289, i64 6, !dbg !401
  %t329 = load i8, ptr %t328, align 1, !dbg !401
  %t330 = insertelement <16 x i8> %t327, i8 %t329, i32 6, !dbg !401
  br label %tail.lane.70, !dbg !401
tail.lane.70:
  %t331 = phi <16 x i8> [ zeroinitializer, %simd.no.63 ], [ %t330, %tail.lane.71 ], !dbg !401
  %t332 = getelementptr inbounds i8, ptr %t289, i64 5, !dbg !401
  %t333 = load i8, ptr %t332, align 1, !dbg !401
  %t334 = insertelement <16 x i8> %t331, i8 %t333, i32 5, !dbg !401
  br label %tail.lane.69, !dbg !401
tail.lane.69:
  %t335 = phi <16 x i8> [ zeroinitializer, %simd.no.63 ], [ %t334, %tail.lane.70 ], !dbg !401
  %t336 = getelementptr inbounds i8, ptr %t289, i64 4, !dbg !401
  %t337 = load i8, ptr %t336, align 1, !dbg !401
  %t338 = insertelement <16 x i8> %t335, i8 %t337, i32 4, !dbg !401
  br label %tail.lane.68, !dbg !401
tail.lane.68:
  %t339 = phi <16 x i8> [ zeroinitializer, %simd.no.63 ], [ %t338, %tail.lane.69 ], !dbg !401
  %t340 = getelementptr inbounds i8, ptr %t289, i64 3, !dbg !401
  %t341 = load i8, ptr %t340, align 1, !dbg !401
  %t342 = insertelement <16 x i8> %t339, i8 %t341, i32 3, !dbg !401
  br label %tail.lane.67, !dbg !401
tail.lane.67:
  %t343 = phi <16 x i8> [ zeroinitializer, %simd.no.63 ], [ %t342, %tail.lane.68 ], !dbg !401
  %t344 = getelementptr inbounds i8, ptr %t289, i64 2, !dbg !401
  %t345 = load i8, ptr %t344, align 1, !dbg !401
  %t346 = insertelement <16 x i8> %t343, i8 %t345, i32 2, !dbg !401
  br label %tail.lane.66, !dbg !401
tail.lane.66:
  %t347 = phi <16 x i8> [ zeroinitializer, %simd.no.63 ], [ %t346, %tail.lane.67 ], !dbg !401
  %t348 = getelementptr inbounds i8, ptr %t289, i64 1, !dbg !401
  %t349 = load i8, ptr %t348, align 1, !dbg !401
  %t350 = insertelement <16 x i8> %t347, i8 %t349, i32 1, !dbg !401
  br label %tail.lane.65, !dbg !401
tail.lane.65:
  %t351 = phi <16 x i8> [ zeroinitializer, %simd.no.63 ], [ %t350, %tail.lane.66 ], !dbg !401
  %t352 = getelementptr inbounds i8, ptr %t289, i64 0, !dbg !401
  %t353 = load i8, ptr %t352, align 1, !dbg !401
  %t354 = insertelement <16 x i8> %t351, i8 %t353, i32 0, !dbg !401
  br label %tail.done.81, !dbg !401
tail.done.81:
  %t355 = phi <16 x i8> [ zeroinitializer, %simd.no.63 ], [ %t354, %tail.lane.65 ], !dbg !401
  br label %simd.join.64, !dbg !401
simd.join.64:
  %t356 = phi <16 x i8> [ %t291, %simd.yes.62 ], [ %t355, %tail.done.81 ], !dbg !401
  store <16 x i8> %t356, ptr %slot357, !dbg !401
  %t358 = load <16 x i8>, ptr %slot357, !dbg !402
  %t359 = load <16 x i8>, ptr %slot168, !dbg !402
  %t360 = shufflevector <16 x i8> %t358, <16 x i8> %t359, <16 x i32> <i32 15, i32 16, i32 17, i32 18, i32 19, i32 20, i32 21, i32 22, i32 23, i32 24, i32 25, i32 26, i32 27, i32 28, i32 29, i32 30>, !dbg !402
  store <16 x i8> %t360, ptr %slot361, !dbg !402
  %t362 = load <16 x i8>, ptr %slot357, !dbg !403
  %t363 = load <16 x i8>, ptr %slot168, !dbg !403
  %t364 = shufflevector <16 x i8> %t362, <16 x i8> %t363, <16 x i32> <i32 14, i32 15, i32 16, i32 17, i32 18, i32 19, i32 20, i32 21, i32 22, i32 23, i32 24, i32 25, i32 26, i32 27, i32 28, i32 29>, !dbg !403
  store <16 x i8> %t364, ptr %slot365, !dbg !403
  %t366 = load <16 x i8>, ptr %slot357, !dbg !404
  %t367 = load <16 x i8>, ptr %slot168, !dbg !404
  %t368 = shufflevector <16 x i8> %t366, <16 x i8> %t367, <16 x i32> <i32 13, i32 14, i32 15, i32 16, i32 17, i32 18, i32 19, i32 20, i32 21, i32 22, i32 23, i32 24, i32 25, i32 26, i32 27, i32 28>, !dbg !404
  store <16 x i8> %t368, ptr %slot369, !dbg !404
  %t370 = call i32 @nupp.wrap.u32(double 0x0000000000000000), !dbg !405
  %t371 = trunc i32 %t370 to i8, !dbg !405
  %t372 = insertelement <16 x i8> poison, i8 %t371, i64 0, !dbg !405
  %t373 = shufflevector <16 x i8> %t372, <16 x i8> poison, <16 x i32> zeroinitializer, !dbg !405
  store <16 x i8> %t373, ptr %slot374, !dbg !405
  %t375 = load <16 x i8>, ptr %slot374, !dbg !406
  %t376 = call <16 x i8> @ks___nupp_const_decode_fused_a640dbc37ebbc1be__5f5f6e757070436f6e73745f6465636f646546757365645f61363430646263333765626263316265_helper_nibble_table(<16 x i8> %t375, i32 2, i32 2, i32 2, i32 2, i32 2, i32 2, i32 2, i32 2, i32 128, i32 128, i32 128, i32 128, i32 33, i32 1, i32 21, i32 73), !dbg !406
  store <16 x i8> %t376, ptr %slot377, !dbg !406
  %t378 = load <16 x i8>, ptr %slot374, !dbg !407
  %t379 = call <16 x i8> @ks___nupp_const_decode_fused_a640dbc37ebbc1be__5f5f6e757070436f6e73745f6465636f646546757365645f61363430646263333765626263316265_helper_nibble_table(<16 x i8> %t378, i32 231, i32 163, i32 131, i32 131, i32 139, i32 203, i32 203, i32 203, i32 203, i32 203, i32 203, i32 203, i32 203, i32 219, i32 203, i32 203), !dbg !407
  store <16 x i8> %t379, ptr %slot380, !dbg !407
  %t381 = load <16 x i8>, ptr %slot374, !dbg !408
  %t382 = call <16 x i8> @ks___nupp_const_decode_fused_a640dbc37ebbc1be__5f5f6e757070436f6e73745f6465636f646546757365645f61363430646263333765626263316265_helper_nibble_table(<16 x i8> %t381, i32 1, i32 1, i32 1, i32 1, i32 1, i32 1, i32 1, i32 1, i32 230, i32 174, i32 186, i32 186, i32 1, i32 1, i32 1, i32 1), !dbg !408
  store <16 x i8> %t382, ptr %slot383, !dbg !408
  %t384 = load <16 x i8>, ptr %slot377, !dbg !409
  %t385 = load <16 x i8>, ptr %slot361, !dbg !409
  %t386 = call i32 @nupp.wrap.u32(double 0x4010000000000000), !dbg !409
  %t387 = trunc i32 %t386 to i8, !dbg !409
  %t388 = insertelement <16 x i8> poison, i8 %t387, i64 0, !dbg !409
  %t389 = shufflevector <16 x i8> %t388, <16 x i8> poison, <16 x i32> zeroinitializer, !dbg !409
  %t390 = and <16 x i8> %t389, splat (i8 7), !dbg !409
  %t391 = lshr <16 x i8> %t385, %t390, !dbg !409
  %t392 = call i32 @nupp.wrap.u32(double 0x3FF0000000000000), !dbg !409
  %t393 = trunc i32 %t392 to i8, !dbg !409
  %t394 = insertelement <16 x i8> poison, i8 %t393, i64 0, !dbg !409
  %t395 = shufflevector <16 x i8> %t394, <16 x i8> poison, <16 x i32> zeroinitializer, !dbg !409
  %t396 = add <16 x i8> %t391, %t395, !dbg !409
  %t397 = sub <16 x i8> %t396, splat (i8 1), !dbg !409
  %t398 = call <16 x i8> @llvm.aarch64.neon.tbl1.v16i8(<16 x i8> %t384, <16 x i8> %t397), !dbg !409
  %t399 = load <16 x i8>, ptr %slot380, !dbg !409
  %t400 = load <16 x i8>, ptr %slot361, !dbg !409
  %t401 = call i32 @nupp.wrap.u32(double 0x402E000000000000), !dbg !409
  %t402 = trunc i32 %t401 to i8, !dbg !409
  %t403 = insertelement <16 x i8> poison, i8 %t402, i64 0, !dbg !409
  %t404 = shufflevector <16 x i8> %t403, <16 x i8> poison, <16 x i32> zeroinitializer, !dbg !409
  %t405 = and <16 x i8> %t400, %t404, !dbg !409
  %t406 = call i32 @nupp.wrap.u32(double 0x3FF0000000000000), !dbg !409
  %t407 = trunc i32 %t406 to i8, !dbg !409
  %t408 = insertelement <16 x i8> poison, i8 %t407, i64 0, !dbg !409
  %t409 = shufflevector <16 x i8> %t408, <16 x i8> poison, <16 x i32> zeroinitializer, !dbg !409
  %t410 = add <16 x i8> %t405, %t409, !dbg !409
  %t411 = sub <16 x i8> %t410, splat (i8 1), !dbg !409
  %t412 = call <16 x i8> @llvm.aarch64.neon.tbl1.v16i8(<16 x i8> %t399, <16 x i8> %t411), !dbg !409
  %t413 = and <16 x i8> %t398, %t412, !dbg !409
  %t414 = load <16 x i8>, ptr %slot383, !dbg !409
  %t415 = load <16 x i8>, ptr %slot168, !dbg !409
  %t416 = call i32 @nupp.wrap.u32(double 0x4010000000000000), !dbg !409
  %t417 = trunc i32 %t416 to i8, !dbg !409
  %t418 = insertelement <16 x i8> poison, i8 %t417, i64 0, !dbg !409
  %t419 = shufflevector <16 x i8> %t418, <16 x i8> poison, <16 x i32> zeroinitializer, !dbg !409
  %t420 = and <16 x i8> %t419, splat (i8 7), !dbg !409
  %t421 = lshr <16 x i8> %t415, %t420, !dbg !409
  %t422 = call i32 @nupp.wrap.u32(double 0x3FF0000000000000), !dbg !409
  %t423 = trunc i32 %t422 to i8, !dbg !409
  %t424 = insertelement <16 x i8> poison, i8 %t423, i64 0, !dbg !409
  %t425 = shufflevector <16 x i8> %t424, <16 x i8> poison, <16 x i32> zeroinitializer, !dbg !409
  %t426 = add <16 x i8> %t421, %t425, !dbg !409
  %t427 = sub <16 x i8> %t426, splat (i8 1), !dbg !409
  %t428 = call <16 x i8> @llvm.aarch64.neon.tbl1.v16i8(<16 x i8> %t414, <16 x i8> %t427), !dbg !409
  %t429 = and <16 x i8> %t413, %t428, !dbg !409
  store <16 x i8> %t429, ptr %slot430, !dbg !409
  %t431 = call i32 @nupp.wrap.u32(double 0x4060000000000000), !dbg !410
  %t432 = trunc i32 %t431 to i8, !dbg !410
  %t433 = insertelement <16 x i8> poison, i8 %t432, i64 0, !dbg !410
  %t434 = shufflevector <16 x i8> %t433, <16 x i8> poison, <16 x i32> zeroinitializer, !dbg !410
  %t435 = call i32 @nupp.wrap.u32(double 0x0000000000000000), !dbg !410
  %t436 = trunc i32 %t435 to i8, !dbg !410
  %t437 = insertelement <16 x i8> poison, i8 %t436, i64 0, !dbg !410
  %t438 = shufflevector <16 x i8> %t437, <16 x i8> poison, <16 x i32> zeroinitializer, !dbg !410
  %t439 = load <16 x i8>, ptr %slot365, !dbg !410
  %t440 = call i32 @nupp.wrap.u32(double 0x406C000000000000), !dbg !410
  %t441 = trunc i32 %t440 to i8, !dbg !410
  %t442 = insertelement <16 x i8> poison, i8 %t441, i64 0, !dbg !410
  %t443 = shufflevector <16 x i8> %t442, <16 x i8> poison, <16 x i32> zeroinitializer, !dbg !410
  %t444 = icmp uge <16 x i8> %t439, %t443, !dbg !410
  %t445 = load <16 x i8>, ptr %slot369, !dbg !410
  %t446 = call i32 @nupp.wrap.u32(double 0x406E000000000000), !dbg !410
  %t447 = trunc i32 %t446 to i8, !dbg !410
  %t448 = insertelement <16 x i8> poison, i8 %t447, i64 0, !dbg !410
  %t449 = shufflevector <16 x i8> %t448, <16 x i8> poison, <16 x i32> zeroinitializer, !dbg !410
  %t450 = icmp uge <16 x i8> %t445, %t449, !dbg !410
  %t451 = or <16 x i1> %t444, %t450, !dbg !410
  %t452 = select <16 x i1> %t451, <16 x i8> %t434, <16 x i8> %t438, !dbg !410
  store <16 x i8> %t452, ptr %slot453, !dbg !410
  %t454 = load <16 x i8>, ptr %slot430, !dbg !411
  %t455 = load <16 x i8>, ptr %slot453, !dbg !411
  %t456 = xor <16 x i8> %t454, %t455, !dbg !411
  %t457 = call i32 @nupp.wrap.u32(double 0x0000000000000000), !dbg !411
  %t458 = trunc i32 %t457 to i8, !dbg !411
  %t459 = zext i8 %t458 to i32, !dbg !411
  %t460 = call i32 @llvm.aarch64.neon.umaxv.i32.v16i8(<16 x i8> %t456), !dbg !411
  %t461 = trunc i32 %t460 to i8, !dbg !411
  %t462 = zext i8 %t461 to i32, !dbg !411
  %t463 = icmp ne i32 %t462, 0, !dbg !411
  br i1 %t463, label %if.then.83, label %if.else.84, !dbg !411
if.then.83:
  store i1 true, ptr %slot56, !dbg !412
  br label %if.end.82, !dbg !412
if.else.84:
  %t464 = load <16 x i8>, ptr %slot168, !dbg !413
  %t465 = load <16 x i8>, ptr %slot168, !dbg !413
  %t466 = shufflevector <16 x i8> %t464, <16 x i8> %t465, <16 x i32> <i32 15, i32 16, i32 17, i32 18, i32 19, i32 20, i32 21, i32 22, i32 23, i32 24, i32 25, i32 26, i32 27, i32 28, i32 29, i32 30>, !dbg !413
  %t467 = extractelement <16 x i8> %t466, i32 0, !dbg !413
  %t468 = zext i8 %t467 to i32, !dbg !413
  %t469 = icmp uge i32 %t468, 128, !dbg !413
  store i1 %t469, ptr %slot50, !dbg !413
  br label %if.end.82, !dbg !413
if.end.82:
  br label %if.end.59, !dbg !413
if.else.61:
  store i1 false, ptr %slot50, !dbg !414
  br label %if.end.59, !dbg !414
if.end.59:
  %t470 = load i1, ptr %slot56, !dbg !415
  %t471 = xor i1 %t470, true, !dbg !415
  br i1 %t471, label %if.then.86, label %if.else.87, !dbg !415
if.then.86:
  store i32 16, ptr %slot70, !dbg !416
  br label %if.end.85, !dbg !416
if.else.87:
  %t472 = call i64 @llvm.fptosi.sat.i64.f64(double 0x0000000000000000), !dbg !417
  %t473 = call i64 @llvm.fptoui.sat.i64.f64(double 0x0000000000000000), !dbg !417
  %t474 = fcmp olt double 0x0000000000000000, 0.0, !dbg !417
  %t475 = select i1 %t474, i64 %t472, i64 %t473, !dbg !417
  store i64 %t475, ptr %slot68, !dbg !417
  br label %if.end.85, !dbg !417
if.end.85:
  br label %if.end.22, !dbg !417
if.else.26:
  br label %if.end.22, !dbg !417
if.end.22:
  br label %if.end.19, !dbg !417
if.else.21:
  br label %if.end.19, !dbg !417
if.end.19:
  %t476 = load i32, ptr %slot70, !dbg !418
  %t477 = icmp eq i32 %t476, 0, !dbg !418
  br i1 %t477, label %and.rhs.89, label %and.end.90, !dbg !418
and.rhs.89:
  %t478 = load i1, ptr %slot49, !dbg !418
  %t479 = xor i1 %t478, true, !dbg !418
  br label %and.end.90, !dbg !418
and.end.90:
  %t480 = phi i1 [ false, %if.end.19 ], [ %t479, %and.rhs.89 ], !dbg !418
  br i1 %t480, label %if.then.91, label %if.else.92, !dbg !418
if.then.91:
  store i1 true, ptr %slot49, !dbg !419
  %t481 = call i32 @nupp.wrap.u32(double 0x3FF0000000000000), !dbg !420
  store i32 %t481, ptr %slot482, !dbg !420
  store i1 true, ptr %slot483, !dbg !421
  br label %while.head.93, !dbg !422
while.head.93:
  %t484 = load i1, ptr %slot483, !dbg !422
  br i1 %t484, label %and.rhs.96, label %and.end.97, !dbg !422
and.rhs.96:
  %t485 = load i32, ptr %slot482, !dbg !422
  %t486 = icmp ule i32 %t485, 3, !dbg !422
  br label %and.end.97, !dbg !422
and.end.97:
  %t487 = phi i1 [ false, %while.head.93 ], [ %t486, %and.rhs.96 ], !dbg !422
  br i1 %t487, label %and.rhs.98, label %and.end.99, !dbg !422
and.rhs.98:
  %t488 = load i32, ptr %slot482, !dbg !422
  %t489 = load i32, ptr %slot33, !dbg !422
  %t490 = icmp ule i32 %t488, %t489, !dbg !422
  br label %and.end.99, !dbg !422
and.end.99:
  %t491 = phi i1 [ false, %and.end.97 ], [ %t490, %and.rhs.98 ], !dbg !422
  br i1 %t491, label %while.body.94, label %while.end.95, !dbg !422
while.body.94:
  %t492 = load i32, ptr %slot33, !dbg !423
  %t493 = load i32, ptr %slot482, !dbg !423
  %t494 = sub i32 %t492, %t493, !dbg !423
  %t495 = zext i32 %t494 to i64, !dbg !423
  %t496 = icmp uge i64 %t495, %t15, !dbg !423
  br i1 %t496, label %lua.raise.100, label %lua.ok.101, !prof !7, !dbg !423
lua.raise.100:
  %t497 = getelementptr inbounds ptr, ptr %t1, i64 11, !dbg !423
  %rt.raise.498 = load ptr, ptr %t497, !invariant.load !8, !dbg !423
  call void %rt.raise.498(ptr %L, i64 3) nomerge, !dbg !423
  unreachable, !dbg !423
lua.ok.101:
  %t499 = getelementptr inbounds i8, ptr %t14, i64 %t495, !dbg !423
  %t500 = load i8, ptr %t499, !dbg !423
  %t501 = zext i8 %t500 to i32, !dbg !423
  store i32 %t501, ptr %slot502, !dbg !423
  %t503 = load i32, ptr %slot502, !dbg !424
  %t504 = icmp ult i32 %t503, 128, !dbg !424
  br i1 %t504, label %if.then.103, label %if.else.104, !dbg !424
if.then.103:
  store i1 false, ptr %slot483, !dbg !425
  br label %if.end.102, !dbg !425
if.else.104:
  %t505 = load i32, ptr %slot502, !dbg !425
  %t506 = icmp uge i32 %t505, 192, !dbg !425
  br i1 %t506, label %if.then.105, label %if.else.106, !dbg !425
if.then.105:
  %t507 = load i32, ptr %slot502, !dbg !426
  %t508 = icmp ult i32 %t507, 194, !dbg !426
  br i1 %t508, label %or.end.109, label %or.rhs.108, !dbg !426
or.rhs.108:
  %t509 = load i32, ptr %slot502, !dbg !426
  %t510 = icmp ugt i32 %t509, 244, !dbg !426
  br label %or.end.109, !dbg !426
or.end.109:
  %t511 = phi i1 [ true, %if.then.105 ], [ %t510, %or.rhs.108 ], !dbg !426
  br i1 %t511, label %if.then.110, label %if.else.111, !dbg !426
if.then.110:
  call void @lua_pushvalue(ptr %L, i32 2), !dbg !427
  %t512 = call i32 @nupp.wrap.u32(double 0x4000000000000000), !dbg !427
  %t513 = uitofp i32 %t512 to double, !dbg !427
  call void @lua_pushnumber(ptr %L, double %t513), !dbg !427
  %t514 = load i32, ptr %slot33, !dbg !427
  %t515 = load i32, ptr %slot482, !dbg !427
  %t516 = sub i32 %t514, %t515, !dbg !427
  %t517 = add i32 %t516, 1, !dbg !427
  %t518 = uitofp i32 %t517 to double, !dbg !427
  call void @lua_pushnumber(ptr %L, double %t518), !dbg !427
  ret i32 3, !dbg !427
if.else.111:
  br label %if.end.107, !dbg !427
if.end.107:
  %t519 = call i32 @nupp.wrap.u32(double 0x4008000000000000), !dbg !428
  store i32 %t519, ptr %slot520, !dbg !428
  %t521 = load i32, ptr %slot502, !dbg !429
  %t522 = icmp ule i32 %t521, 223, !dbg !429
  br i1 %t522, label %if.then.113, label %if.else.114, !dbg !429
if.then.113:
  %t523 = call i32 @nupp.wrap.u32(double 0x3FF0000000000000), !dbg !430
  store i32 %t523, ptr %slot520, !dbg !430
  br label %if.end.112, !dbg !430
if.else.114:
  %t524 = load i32, ptr %slot502, !dbg !430
  %t525 = icmp ule i32 %t524, 239, !dbg !430
  br i1 %t525, label %if.then.115, label %if.else.116, !dbg !430
if.then.115:
  %t526 = call i32 @nupp.wrap.u32(double 0x4000000000000000), !dbg !431
  store i32 %t526, ptr %slot520, !dbg !431
  br label %if.end.112, !dbg !431
if.else.116:
  br label %if.end.112, !dbg !431
if.end.112:
  %t527 = load i32, ptr %slot520, !dbg !432
  %t528 = load i32, ptr %slot482, !dbg !432
  %t529 = icmp uge i32 %t527, %t528, !dbg !432
  br i1 %t529, label %if.then.118, label %if.else.119, !dbg !432
if.then.118:
  %t530 = load i32, ptr %slot520, !dbg !433
  %t531 = load i32, ptr %slot482, !dbg !433
  %t532 = sub i32 %t530, %t531, !dbg !433
  %t533 = add i32 %t532, 1, !dbg !433
  store i32 %t533, ptr %slot43, !dbg !433
  store i1 true, ptr %slot46, !dbg !434
  %t534 = load i32, ptr %slot33, !dbg !435
  %t535 = sub i32 %t534, 1, !dbg !435
  store i32 %t535, ptr %slot48, !dbg !435
  %t536 = load i32, ptr %slot482, !dbg !436
  %t537 = icmp eq i32 %t536, 1, !dbg !436
  br i1 %t537, label %if.then.121, label %if.else.122, !dbg !436
if.then.121:
  %t538 = load i32, ptr %slot502, !dbg !437
  %t539 = icmp eq i32 %t538, 224, !dbg !437
  br i1 %t539, label %if.then.124, label %if.else.125, !dbg !437
if.then.124:
  %t540 = call i32 @nupp.wrap.u32(double 0x3FF0000000000000), !dbg !438
  store i32 %t540, ptr %slot45, !dbg !438
  br label %if.end.123, !dbg !438
if.else.125:
  %t541 = load i32, ptr %slot502, !dbg !438
  %t542 = icmp eq i32 %t541, 237, !dbg !438
  br i1 %t542, label %if.then.126, label %if.else.127, !dbg !438
if.then.126:
  %t543 = call i32 @nupp.wrap.u32(double 0x4000000000000000), !dbg !439
  store i32 %t543, ptr %slot45, !dbg !439
  br label %if.end.123, !dbg !439
if.else.127:
  %t544 = load i32, ptr %slot502, !dbg !439
  %t545 = icmp eq i32 %t544, 240, !dbg !439
  br i1 %t545, label %if.then.128, label %if.else.129, !dbg !439
if.then.128:
  %t546 = call i32 @nupp.wrap.u32(double 0x4008000000000000), !dbg !440
  store i32 %t546, ptr %slot45, !dbg !440
  br label %if.end.123, !dbg !440
if.else.129:
  %t547 = load i32, ptr %slot502, !dbg !440
  %t548 = icmp eq i32 %t547, 244, !dbg !440
  br i1 %t548, label %if.then.130, label %if.else.131, !dbg !440
if.then.130:
  %t549 = call i32 @nupp.wrap.u32(double 0x4010000000000000), !dbg !441
  store i32 %t549, ptr %slot45, !dbg !441
  br label %if.end.123, !dbg !441
if.else.131:
  br label %if.end.123, !dbg !441
if.end.123:
  br label %if.end.120, !dbg !441
if.else.122:
  br label %if.end.120, !dbg !441
if.end.120:
  br label %if.end.117, !dbg !441
if.else.119:
  br label %if.end.117, !dbg !441
if.end.117:
  store i1 false, ptr %slot483, !dbg !442
  br label %if.end.102, !dbg !442
if.else.106:
  %t550 = load i32, ptr %slot482, !dbg !443
  %t551 = add i32 %t550, 1, !dbg !443
  store i32 %t551, ptr %slot482, !dbg !443
  br label %if.end.102, !dbg !443
if.end.102:
  br label %while.head.93, !dbg !443
while.end.95:
  br label %if.end.88, !dbg !443
if.else.92:
  %t552 = load i32, ptr %slot70, !dbg !443
  %t553 = icmp eq i32 %t552, 0, !dbg !443
  br i1 %t553, label %if.then.132, label %if.else.133, !dbg !443
if.then.132:
  %t554 = load i32, ptr %slot33, !dbg !444
  %t555 = load i32, ptr %slot20, !dbg !444
  %t556 = icmp ult i32 %t554, %t555, !dbg !444
  br i1 %t556, label %if.then.135, label %if.else.136, !dbg !444
if.then.135:
  %t557 = load i32, ptr %slot33, !dbg !445
  %t558 = zext i32 %t557 to i64, !dbg !445
  %t559 = getelementptr inbounds i8, ptr %t14, i64 %t558, !dbg !445
  %t560 = load i8, ptr %t559, !dbg !445
  %t561 = zext i8 %t560 to i32, !dbg !445
  store i32 %t561, ptr %slot562, !dbg !445
  %t563 = load i32, ptr %slot562, !dbg !446
  %t564 = icmp eq i32 %t563, 34, !dbg !446
  br i1 %t564, label %or.end.139, label %or.rhs.138, !dbg !446
or.rhs.138:
  %t565 = load i32, ptr %slot562, !dbg !446
  %t566 = icmp eq i32 %t565, 92, !dbg !446
  br label %or.end.139, !dbg !446
or.end.139:
  %t567 = phi i1 [ true, %if.then.135 ], [ %t566, %or.rhs.138 ], !dbg !446
  br i1 %t567, label %or.end.141, label %or.rhs.140, !dbg !446
or.rhs.140:
  %t568 = load i32, ptr %slot562, !dbg !446
  %t569 = icmp ult i32 %t568, 32, !dbg !446
  br label %or.end.141, !dbg !446
or.end.141:
  %t570 = phi i1 [ true, %or.end.139 ], [ %t569, %or.rhs.140 ], !dbg !446
  br i1 %t570, label %or.end.143, label %or.rhs.142, !dbg !446
or.rhs.142:
  %t571 = load i32, ptr %slot562, !dbg !446
  %t572 = icmp eq i32 %t571, 123, !dbg !446
  br label %or.end.143, !dbg !446
or.end.143:
  %t573 = phi i1 [ true, %or.end.141 ], [ %t572, %or.rhs.142 ], !dbg !446
  br i1 %t573, label %or.end.145, label %or.rhs.144, !dbg !446
or.rhs.144:
  %t574 = load i32, ptr %slot562, !dbg !446
  %t575 = icmp eq i32 %t574, 125, !dbg !446
  br label %or.end.145, !dbg !446
or.end.145:
  %t576 = phi i1 [ true, %or.end.143 ], [ %t575, %or.rhs.144 ], !dbg !446
  br i1 %t576, label %or.end.147, label %or.rhs.146, !dbg !446
or.rhs.146:
  %t577 = load i32, ptr %slot562, !dbg !446
  %t578 = icmp eq i32 %t577, 91, !dbg !446
  br label %or.end.147, !dbg !446
or.end.147:
  %t579 = phi i1 [ true, %or.end.145 ], [ %t578, %or.rhs.146 ], !dbg !446
  br i1 %t579, label %or.end.149, label %or.rhs.148, !dbg !446
or.rhs.148:
  %t580 = load i32, ptr %slot562, !dbg !446
  %t581 = icmp eq i32 %t580, 93, !dbg !446
  br label %or.end.149, !dbg !446
or.end.149:
  %t582 = phi i1 [ true, %or.end.147 ], [ %t581, %or.rhs.148 ], !dbg !446
  br i1 %t582, label %or.end.151, label %or.rhs.150, !dbg !446
or.rhs.150:
  %t583 = load i32, ptr %slot562, !dbg !446
  %t584 = icmp eq i32 %t583, 58, !dbg !446
  br label %or.end.151, !dbg !446
or.end.151:
  %t585 = phi i1 [ true, %or.end.149 ], [ %t584, %or.rhs.150 ], !dbg !446
  br i1 %t585, label %or.end.153, label %or.rhs.152, !dbg !446
or.rhs.152:
  %t586 = load i32, ptr %slot562, !dbg !446
  %t587 = icmp eq i32 %t586, 44, !dbg !446
  br label %or.end.153, !dbg !446
or.end.153:
  %t588 = phi i1 [ true, %or.end.151 ], [ %t587, %or.rhs.152 ], !dbg !446
  br i1 %t588, label %or.end.155, label %or.rhs.154, !dbg !446
or.rhs.154:
  %t589 = load i32, ptr %slot562, !dbg !446
  %t590 = icmp uge i32 %t589, 128, !dbg !446
  br label %or.end.155, !dbg !446
or.end.155:
  %t591 = phi i1 [ true, %or.end.153 ], [ %t590, %or.rhs.154 ], !dbg !446
  br i1 %t591, label %if.then.156, label %if.else.157, !dbg !446
if.then.156:
  %t592 = load i64, ptr %slot55, !dbg !447
  store i64 %t592, ptr %slot68, !dbg !447
  br label %if.end.137, !dbg !447
if.else.157:
  br label %if.end.137, !dbg !447
if.end.137:
  br label %if.end.134, !dbg !447
if.else.136:
  br label %if.end.134, !dbg !447
if.end.134:
  %t593 = call i32 @nupp.wrap.u32(double 0x3FF0000000000000), !dbg !448
  store i32 %t593, ptr %slot70, !dbg !448
  br label %if.end.88, !dbg !448
if.else.133:
  br label %if.end.88, !dbg !448
if.end.88:
  br label %while.head.158, !dbg !449
while.head.158:
  %t594 = load i64, ptr %slot68, !dbg !449
  %t595 = call i64 @llvm.fptosi.sat.i64.f64(double 0x0000000000000000), !dbg !449
  %t596 = call i64 @llvm.fptoui.sat.i64.f64(double 0x0000000000000000), !dbg !449
  %t597 = fcmp olt double 0x0000000000000000, 0.0, !dbg !449
  %t598 = select i1 %t597, i64 %t595, i64 %t596, !dbg !449
  %t599 = icmp ne i64 %t594, %t598, !dbg !449
  br i1 %t599, label %while.body.159, label %while.end.160, !dbg !449
while.body.159:
  %t600 = load i64, ptr %slot68, !dbg !450
  %t601 = call i64 @llvm.cttz.i64(i64 %t600, i1 false), !dbg !450
  %t602 = trunc i64 %t601 to i32, !dbg !450
  store i32 %t602, ptr %slot603, !dbg !450
  %t604 = load i64, ptr %slot68, !dbg !451
  %t605 = load i64, ptr %slot68, !dbg !451
  %t606 = call i64 @llvm.fptosi.sat.i64.f64(double 0x3FF0000000000000), !dbg !451
  %t607 = call i64 @llvm.fptoui.sat.i64.f64(double 0x3FF0000000000000), !dbg !451
  %t608 = fcmp olt double 0x3FF0000000000000, 0.0, !dbg !451
  %t609 = select i1 %t608, i64 %t606, i64 %t607, !dbg !451
  %t610 = sub i64 %t605, %t609, !dbg !451
  %t611 = and i64 %t604, %t610, !dbg !451
  store i64 %t611, ptr %slot68, !dbg !451
  %t612 = load i32, ptr %slot33, !dbg !452
  %t613 = load i32, ptr %slot603, !dbg !452
  %t614 = add i32 %t612, %t613, !dbg !452
  store i32 %t614, ptr %slot615, !dbg !452
  %t616 = load i32, ptr %slot615, !dbg !453
  %t617 = load i32, ptr %slot20, !dbg !453
  %t618 = icmp ult i32 %t616, %t617, !dbg !453
  br i1 %t618, label %if.then.162, label %if.else.163, !dbg !453
if.then.162:
  %t619 = load i32, ptr %slot615, !dbg !454
  %t620 = zext i32 %t619 to i64, !dbg !454
  %t621 = getelementptr inbounds i8, ptr %t14, i64 %t620, !dbg !454
  %t622 = load i8, ptr %t621, !dbg !454
  %t623 = zext i8 %t622 to i32, !dbg !454
  store i32 %t623, ptr %slot624, !dbg !454
  %t625 = load i32, ptr %slot43, !dbg !455
  %t626 = icmp ne i32 %t625, 0, !dbg !455
  br i1 %t626, label %and.rhs.165, label %and.end.166, !dbg !455
and.rhs.165:
  %t627 = load i1, ptr %slot46, !dbg !455
  %t628 = xor i1 %t627, true, !dbg !455
  br i1 %t628, label %or.end.168, label %or.rhs.167, !dbg !455
or.rhs.167:
  %t629 = load i32, ptr %slot615, !dbg !455
  %t630 = load i32, ptr %slot48, !dbg !455
  %t631 = add i32 %t630, 1, !dbg !455
  %t632 = icmp ne i32 %t629, %t631, !dbg !455
  br label %or.end.168, !dbg !455
or.end.168:
  %t633 = phi i1 [ true, %and.rhs.165 ], [ %t632, %or.rhs.167 ], !dbg !455
  br label %and.end.166, !dbg !455
and.end.166:
  %t634 = phi i1 [ false, %if.then.162 ], [ %t633, %or.end.168 ], !dbg !455
  br i1 %t634, label %if.then.169, label %if.else.170, !dbg !455
if.then.169:
  call void @lua_pushvalue(ptr %L, i32 2), !dbg !456
  %t635 = call i32 @nupp.wrap.u32(double 0x4000000000000000), !dbg !456
  %t636 = uitofp i32 %t635 to double, !dbg !456
  call void @lua_pushnumber(ptr %L, double %t636), !dbg !456
  %t637 = load i32, ptr %slot48, !dbg !456
  %t638 = add i32 %t637, 2, !dbg !456
  %t639 = uitofp i32 %t638 to double, !dbg !456
  call void @lua_pushnumber(ptr %L, double %t639), !dbg !456
  ret i32 3, !dbg !456
if.else.170:
  br label %if.end.164, !dbg !456
if.end.164:
  %t640 = load i32, ptr %slot624, !dbg !457
  %t641 = icmp uge i32 %t640, 128, !dbg !457
  br i1 %t641, label %if.then.172, label %if.else.173, !dbg !457
if.then.172:
  %t642 = load i32, ptr %slot624, !dbg !458
  %t643 = icmp ule i32 %t642, 191, !dbg !458
  store i1 %t643, ptr %slot644, !dbg !458
  %t645 = load i32, ptr %slot43, !dbg !459
  %t646 = icmp ne i32 %t645, 0, !dbg !459
  br i1 %t646, label %if.then.175, label %if.else.176, !dbg !459
if.then.175:
  %t647 = load i1, ptr %slot644, !dbg !460
  %t648 = xor i1 %t647, true, !dbg !460
  br i1 %t648, label %if.then.178, label %if.else.179, !dbg !460
if.then.178:
  call void @lua_pushvalue(ptr %L, i32 2), !dbg !461
  %t649 = call i32 @nupp.wrap.u32(double 0x4000000000000000), !dbg !461
  %t650 = uitofp i32 %t649 to double, !dbg !461
  call void @lua_pushnumber(ptr %L, double %t650), !dbg !461
  %t651 = load i32, ptr %slot615, !dbg !461
  %t652 = add i32 %t651, 1, !dbg !461
  %t653 = uitofp i32 %t652 to double, !dbg !461
  call void @lua_pushnumber(ptr %L, double %t653), !dbg !461
  ret i32 3, !dbg !461
if.else.179:
  br label %if.end.177, !dbg !461
if.end.177:
  %t654 = load i32, ptr %slot45, !dbg !462
  %t655 = icmp eq i32 %t654, 1, !dbg !462
  br i1 %t655, label %and.rhs.180, label %and.end.181, !dbg !462
and.rhs.180:
  %t656 = load i32, ptr %slot624, !dbg !462
  %t657 = icmp ult i32 %t656, 160, !dbg !462
  br label %and.end.181, !dbg !462
and.end.181:
  %t658 = phi i1 [ false, %if.end.177 ], [ %t657, %and.rhs.180 ], !dbg !462
  br i1 %t658, label %or.end.183, label %or.rhs.182, !dbg !462
or.rhs.182:
  %t659 = load i32, ptr %slot45, !dbg !462
  %t660 = icmp eq i32 %t659, 2, !dbg !462
  br i1 %t660, label %and.rhs.184, label %and.end.185, !dbg !462
and.rhs.184:
  %t661 = load i32, ptr %slot624, !dbg !462
  %t662 = icmp ugt i32 %t661, 159, !dbg !462
  br label %and.end.185, !dbg !462
and.end.185:
  %t663 = phi i1 [ false, %or.rhs.182 ], [ %t662, %and.rhs.184 ], !dbg !462
  br label %or.end.183, !dbg !462
or.end.183:
  %t664 = phi i1 [ true, %and.end.181 ], [ %t663, %and.end.185 ], !dbg !462
  br i1 %t664, label %or.end.187, label %or.rhs.186, !dbg !462
or.rhs.186:
  %t665 = load i32, ptr %slot45, !dbg !462
  %t666 = icmp eq i32 %t665, 3, !dbg !462
  br i1 %t666, label %and.rhs.188, label %and.end.189, !dbg !462
and.rhs.188:
  %t667 = load i32, ptr %slot624, !dbg !462
  %t668 = icmp ult i32 %t667, 144, !dbg !462
  br label %and.end.189, !dbg !462
and.end.189:
  %t669 = phi i1 [ false, %or.rhs.186 ], [ %t668, %and.rhs.188 ], !dbg !462
  br label %or.end.187, !dbg !462
or.end.187:
  %t670 = phi i1 [ true, %or.end.183 ], [ %t669, %and.end.189 ], !dbg !462
  br i1 %t670, label %or.end.191, label %or.rhs.190, !dbg !462
or.rhs.190:
  %t671 = load i32, ptr %slot45, !dbg !462
  %t672 = icmp eq i32 %t671, 4, !dbg !462
  br i1 %t672, label %and.rhs.192, label %and.end.193, !dbg !462
and.rhs.192:
  %t673 = load i32, ptr %slot624, !dbg !462
  %t674 = icmp ugt i32 %t673, 143, !dbg !462
  br label %and.end.193, !dbg !462
and.end.193:
  %t675 = phi i1 [ false, %or.rhs.190 ], [ %t674, %and.rhs.192 ], !dbg !462
  br label %or.end.191, !dbg !462
or.end.191:
  %t676 = phi i1 [ true, %or.end.187 ], [ %t675, %and.end.193 ], !dbg !462
  store i1 %t676, ptr %slot677, !dbg !462
  %t678 = load i1, ptr %slot677, !dbg !463
  br i1 %t678, label %if.then.195, label %if.else.196, !dbg !463
if.then.195:
  call void @lua_pushvalue(ptr %L, i32 2), !dbg !464
  %t679 = call i32 @nupp.wrap.u32(double 0x4000000000000000), !dbg !464
  %t680 = uitofp i32 %t679 to double, !dbg !464
  call void @lua_pushnumber(ptr %L, double %t680), !dbg !464
  %t681 = load i32, ptr %slot615, !dbg !464
  %t682 = add i32 %t681, 1, !dbg !464
  %t683 = uitofp i32 %t682 to double, !dbg !464
  call void @lua_pushnumber(ptr %L, double %t683), !dbg !464
  ret i32 3, !dbg !464
if.else.196:
  br label %if.end.194, !dbg !464
if.end.194:
  %t684 = load i32, ptr %slot43, !dbg !465
  %t685 = sub i32 %t684, 1, !dbg !465
  store i32 %t685, ptr %slot43, !dbg !465
  %t686 = call i32 @nupp.wrap.u32(double 0x0000000000000000), !dbg !466
  store i32 %t686, ptr %slot45, !dbg !466
  br label %if.end.174, !dbg !466
if.else.176:
  %t687 = load i1, ptr %slot644, !dbg !466
  br i1 %t687, label %or.end.198, label %or.rhs.197, !dbg !466
or.rhs.197:
  %t688 = load i32, ptr %slot624, !dbg !466
  %t689 = icmp ult i32 %t688, 194, !dbg !466
  br label %or.end.198, !dbg !466
or.end.198:
  %t690 = phi i1 [ true, %if.else.176 ], [ %t689, %or.rhs.197 ], !dbg !466
  br i1 %t690, label %or.end.200, label %or.rhs.199, !dbg !466
or.rhs.199:
  %t691 = load i32, ptr %slot624, !dbg !466
  %t692 = icmp ugt i32 %t691, 244, !dbg !466
  br label %or.end.200, !dbg !466
or.end.200:
  %t693 = phi i1 [ true, %or.end.198 ], [ %t692, %or.rhs.199 ], !dbg !466
  br i1 %t693, label %if.then.201, label %if.else.202, !dbg !466
if.then.201:
  call void @lua_pushvalue(ptr %L, i32 2), !dbg !467
  %t694 = call i32 @nupp.wrap.u32(double 0x4000000000000000), !dbg !467
  %t695 = uitofp i32 %t694 to double, !dbg !467
  call void @lua_pushnumber(ptr %L, double %t695), !dbg !467
  %t696 = load i32, ptr %slot615, !dbg !467
  %t697 = add i32 %t696, 1, !dbg !467
  %t698 = uitofp i32 %t697 to double, !dbg !467
  call void @lua_pushnumber(ptr %L, double %t698), !dbg !467
  ret i32 3, !dbg !467
if.else.202:
  %t699 = load i32, ptr %slot624, !dbg !467
  %t700 = icmp ule i32 %t699, 223, !dbg !467
  br i1 %t700, label %if.then.203, label %if.else.204, !dbg !467
if.then.203:
  %t701 = call i32 @nupp.wrap.u32(double 0x3FF0000000000000), !dbg !468
  store i32 %t701, ptr %slot43, !dbg !468
  br label %if.end.174, !dbg !468
if.else.204:
  %t702 = load i32, ptr %slot624, !dbg !468
  %t703 = icmp ule i32 %t702, 239, !dbg !468
  br i1 %t703, label %if.then.205, label %if.else.206, !dbg !468
if.then.205:
  %t704 = call i32 @nupp.wrap.u32(double 0x4000000000000000), !dbg !469
  store i32 %t704, ptr %slot43, !dbg !469
  %t705 = load i32, ptr %slot624, !dbg !470
  %t706 = icmp eq i32 %t705, 224, !dbg !470
  br i1 %t706, label %if.then.208, label %if.else.209, !dbg !470
if.then.208:
  %t707 = call i32 @nupp.wrap.u32(double 0x3FF0000000000000), !dbg !471
  store i32 %t707, ptr %slot45, !dbg !471
  br label %if.end.207, !dbg !471
if.else.209:
  %t708 = load i32, ptr %slot624, !dbg !471
  %t709 = icmp eq i32 %t708, 237, !dbg !471
  br i1 %t709, label %if.then.210, label %if.else.211, !dbg !471
if.then.210:
  %t710 = call i32 @nupp.wrap.u32(double 0x4000000000000000), !dbg !472
  store i32 %t710, ptr %slot45, !dbg !472
  br label %if.end.207, !dbg !472
if.else.211:
  br label %if.end.207, !dbg !472
if.end.207:
  br label %if.end.174, !dbg !472
if.else.206:
  %t711 = call i32 @nupp.wrap.u32(double 0x4008000000000000), !dbg !473
  store i32 %t711, ptr %slot43, !dbg !473
  %t712 = load i32, ptr %slot624, !dbg !474
  %t713 = icmp eq i32 %t712, 240, !dbg !474
  br i1 %t713, label %if.then.213, label %if.else.214, !dbg !474
if.then.213:
  %t714 = call i32 @nupp.wrap.u32(double 0x4008000000000000), !dbg !475
  store i32 %t714, ptr %slot45, !dbg !475
  br label %if.end.212, !dbg !475
if.else.214:
  %t715 = load i32, ptr %slot624, !dbg !475
  %t716 = icmp eq i32 %t715, 244, !dbg !475
  br i1 %t716, label %if.then.215, label %if.else.216, !dbg !475
if.then.215:
  %t717 = call i32 @nupp.wrap.u32(double 0x4010000000000000), !dbg !476
  store i32 %t717, ptr %slot45, !dbg !476
  br label %if.end.212, !dbg !476
if.else.216:
  br label %if.end.212, !dbg !476
if.end.212:
  br label %if.end.174, !dbg !476
if.end.174:
  store i1 true, ptr %slot46, !dbg !477
  %t718 = load i32, ptr %slot615, !dbg !478
  store i32 %t718, ptr %slot48, !dbg !478
  store i1 false, ptr %slot39, !dbg !479
  store i1 false, ptr %slot38, !dbg !480
  br label %if.end.171, !dbg !480
if.else.173:
  %t719 = load i32, ptr %slot43, !dbg !480
  %t720 = icmp ne i32 %t719, 0, !dbg !480
  br i1 %t720, label %if.then.217, label %if.else.218, !dbg !480
if.then.217:
  call void @lua_pushvalue(ptr %L, i32 2), !dbg !481
  %t721 = call i32 @nupp.wrap.u32(double 0x4000000000000000), !dbg !481
  %t722 = uitofp i32 %t721 to double, !dbg !481
  call void @lua_pushnumber(ptr %L, double %t722), !dbg !481
  %t723 = load i32, ptr %slot615, !dbg !481
  %t724 = add i32 %t723, 1, !dbg !481
  %t725 = uitofp i32 %t724 to double, !dbg !481
  call void @lua_pushnumber(ptr %L, double %t725), !dbg !481
  ret i32 3, !dbg !481
if.else.218:
  %t726 = load i32, ptr %slot624, !dbg !481
  %t727 = icmp eq i32 %t726, 92, !dbg !481
  br i1 %t727, label %if.then.219, label %if.else.220, !dbg !481
if.then.219:
  %t728 = load i1, ptr %slot36, !dbg !482
  %t729 = xor i1 %t728, true, !dbg !482
  br i1 %t729, label %if.then.222, label %if.else.223, !dbg !482
if.then.222:
  call void @lua_pushvalue(ptr %L, i32 2), !dbg !483
  %t730 = call i32 @nupp.wrap.u32(double 0x4010000000000000), !dbg !483
  %t731 = uitofp i32 %t730 to double, !dbg !483
  call void @lua_pushnumber(ptr %L, double %t731), !dbg !483
  %t732 = load i32, ptr %slot615, !dbg !483
  %t733 = add i32 %t732, 1, !dbg !483
  %t734 = uitofp i32 %t733 to double, !dbg !483
  call void @lua_pushnumber(ptr %L, double %t734), !dbg !483
  ret i32 3, !dbg !483
if.else.223:
  br label %if.end.221, !dbg !483
if.end.221:
  %t735 = load i1, ptr %slot39, !dbg !484
  br i1 %t735, label %and.rhs.225, label %and.end.226, !dbg !484
and.rhs.225:
  %t736 = load i32, ptr %slot615, !dbg !484
  %t737 = load i32, ptr %slot41, !dbg !484
  %t738 = add i32 %t737, 1, !dbg !484
  %t739 = icmp eq i32 %t736, %t738, !dbg !484
  br label %and.end.226, !dbg !484
and.end.226:
  %t740 = phi i1 [ false, %if.end.221 ], [ %t739, %and.rhs.225 ], !dbg !484
  br i1 %t740, label %if.then.227, label %if.else.228, !dbg !484
if.then.227:
  %t741 = load i1, ptr %slot38, !dbg !485
  %t742 = xor i1 %t741, true, !dbg !485
  store i1 %t742, ptr %slot38, !dbg !485
  br label %if.end.224, !dbg !485
if.else.228:
  store i1 true, ptr %slot38, !dbg !486
  br label %if.end.224, !dbg !486
if.end.224:
  store i1 true, ptr %slot39, !dbg !487
  %t743 = load i32, ptr %slot615, !dbg !488
  store i32 %t743, ptr %slot41, !dbg !488
  store i1 true, ptr %slot37, !dbg !489
  br label %if.end.171, !dbg !489
if.else.220:
  %t744 = load i1, ptr %slot39, !dbg !490
  br i1 %t744, label %and.rhs.229, label %and.end.230, !dbg !490
and.rhs.229:
  %t745 = load i32, ptr %slot615, !dbg !490
  %t746 = load i32, ptr %slot41, !dbg !490
  %t747 = add i32 %t746, 1, !dbg !490
  %t748 = icmp eq i32 %t745, %t747, !dbg !490
  br label %and.end.230, !dbg !490
and.end.230:
  %t749 = phi i1 [ false, %if.else.220 ], [ %t748, %and.rhs.229 ], !dbg !490
  br i1 %t749, label %and.rhs.231, label %and.end.232, !dbg !490
and.rhs.231:
  %t750 = load i1, ptr %slot38, !dbg !490
  br label %and.end.232, !dbg !490
and.end.232:
  %t751 = phi i1 [ false, %and.end.230 ], [ %t750, %and.rhs.231 ], !dbg !490
  store i1 %t751, ptr %slot752, !dbg !490
  %t753 = load i32, ptr %slot624, !dbg !491
  %t754 = icmp eq i32 %t753, 34, !dbg !491
  br i1 %t754, label %and.rhs.234, label %and.end.235, !dbg !491
and.rhs.234:
  %t755 = load i1, ptr %slot752, !dbg !491
  %t756 = xor i1 %t755, true, !dbg !491
  br label %and.end.235, !dbg !491
and.end.235:
  %t757 = phi i1 [ false, %and.end.232 ], [ %t756, %and.rhs.234 ], !dbg !491
  br i1 %t757, label %if.then.236, label %if.else.237, !dbg !491
if.then.236:
  %t758 = load i1, ptr %slot36, !dbg !492
  br i1 %t758, label %if.then.239, label %if.else.240, !dbg !492
if.then.239:
  %t759 = load i32, ptr %slot615, !dbg !493
  store i32 %t759, ptr %slot760, !dbg !493
  %t761 = load i1, ptr %slot37, !dbg !494
  br i1 %t761, label %if.then.242, label %if.else.243, !dbg !494
if.then.242:
  %t762 = load i32, ptr %slot615, !dbg !495
  %t763 = or i32 %t762, 2147483648, !dbg !495
  store i32 %t763, ptr %slot760, !dbg !495
  br label %if.end.241, !dbg !495
if.else.243:
  br label %if.end.241, !dbg !495
if.end.241:
  %t764 = load i32, ptr %slot35, !dbg !496
  %t765 = load i32, ptr %slot760, !dbg !496
  %t766 = getelementptr inbounds { ptr, i32, i32, i32, i32, [32 x i32] }, ptr %slot27, i32 0, i32 2, !dbg !496
  %t767 = load i32, ptr %t766, !dbg !496
  %t768 = getelementptr inbounds { ptr, i32, i32, i32, i32, [32 x i32] }, ptr %slot27, i32 0, i32 1, !dbg !496
  %t769 = load i32, ptr %t768, !dbg !496
  %t770 = icmp ugt i32 %t764, %t767, !dbg !496
  %t771 = icmp uge i32 %t764, %t769, !dbg !496
  %t772 = or i1 %t770, %t771, !dbg !496
  br i1 %t772, label %lua.raise.244, label %lua.ok.245, !prof !7, !dbg !496
lua.raise.244:
  %t773 = getelementptr inbounds ptr, ptr %t1, i64 11, !dbg !496
  %rt.raise.774 = load ptr, ptr %t773, !invariant.load !8, !dbg !496
  call void %rt.raise.774(ptr %L, i64 8) nomerge, !dbg !496
  unreachable, !dbg !496
lua.ok.245:
  %t775 = icmp eq i32 %t764, %t767, !dbg !496
  %t776 = add i32 %t767, 1, !dbg !496
  %t777 = select i1 %t775, i32 %t776, i32 %t767, !dbg !496
  store i32 %t777, ptr %t766, !dbg !496
  %t778 = getelementptr inbounds { ptr, i32, i32, i32, i32, [32 x i32] }, ptr %slot27, i32 0, i32 0, !dbg !496
  %t779 = load ptr, ptr %t778, !dbg !496
  %t780 = zext i32 %t764 to i64, !dbg !496
  %t781 = getelementptr inbounds i32, ptr %t779, i64 %t780, !dbg !496
  store i32 %t765, ptr %t781, !dbg !496
  store i1 false, ptr %slot36, !dbg !497
  br label %if.end.238, !dbg !497
if.else.240:
  %t782 = load i32, ptr %slot35, !dbg !498
  %t783 = load i32, ptr %slot615, !dbg !498
  %t784 = getelementptr inbounds { ptr, i32, i32, i32, i32, [32 x i32] }, ptr %slot27, i32 0, i32 2, !dbg !498
  %t785 = load i32, ptr %t784, !dbg !498
  %t786 = getelementptr inbounds { ptr, i32, i32, i32, i32, [32 x i32] }, ptr %slot27, i32 0, i32 1, !dbg !498
  %t787 = load i32, ptr %t786, !dbg !498
  %t788 = icmp ugt i32 %t782, %t785, !dbg !498
  %t789 = icmp uge i32 %t782, %t787, !dbg !498
  %t790 = or i1 %t788, %t789, !dbg !498
  br i1 %t790, label %lua.raise.246, label %lua.ok.247, !prof !7, !dbg !498
lua.raise.246:
  %t791 = getelementptr inbounds ptr, ptr %t1, i64 11, !dbg !498
  %rt.raise.792 = load ptr, ptr %t791, !invariant.load !8, !dbg !498
  call void %rt.raise.792(ptr %L, i64 8) nomerge, !dbg !498
  unreachable, !dbg !498
lua.ok.247:
  %t793 = icmp eq i32 %t782, %t785, !dbg !498
  %t794 = add i32 %t785, 1, !dbg !498
  %t795 = select i1 %t793, i32 %t794, i32 %t785, !dbg !498
  store i32 %t795, ptr %t784, !dbg !498
  %t796 = getelementptr inbounds { ptr, i32, i32, i32, i32, [32 x i32] }, ptr %slot27, i32 0, i32 0, !dbg !498
  %t797 = load ptr, ptr %t796, !dbg !498
  %t798 = zext i32 %t782 to i64, !dbg !498
  %t799 = getelementptr inbounds i32, ptr %t797, i64 %t798, !dbg !498
  store i32 %t783, ptr %t799, !dbg !498
  store i1 true, ptr %slot36, !dbg !499
  store i1 false, ptr %slot37, !dbg !500
  br label %if.end.238, !dbg !500
if.end.238:
  %t800 = load i32, ptr %slot35, !dbg !501
  %t801 = add i32 %t800, 1, !dbg !501
  store i32 %t801, ptr %slot35, !dbg !501
  br label %if.end.233, !dbg !501
if.else.237:
  %t802 = load i32, ptr %slot624, !dbg !501
  %t803 = icmp ult i32 %t802, 32, !dbg !501
  br i1 %t803, label %if.then.248, label %if.else.249, !dbg !501
if.then.248:
  %t804 = load i32, ptr %slot624, !dbg !502
  %t805 = icmp eq i32 %t804, 9, !dbg !502
  br i1 %t805, label %or.end.251, label %or.rhs.250, !dbg !502
or.rhs.250:
  %t806 = load i32, ptr %slot624, !dbg !502
  %t807 = icmp eq i32 %t806, 10, !dbg !502
  br label %or.end.251, !dbg !502
or.end.251:
  %t808 = phi i1 [ true, %if.then.248 ], [ %t807, %or.rhs.250 ], !dbg !502
  br i1 %t808, label %or.end.253, label %or.rhs.252, !dbg !502
or.rhs.252:
  %t809 = load i32, ptr %slot624, !dbg !502
  %t810 = icmp eq i32 %t809, 13, !dbg !502
  br label %or.end.253, !dbg !502
or.end.253:
  %t811 = phi i1 [ true, %or.end.251 ], [ %t810, %or.rhs.252 ], !dbg !502
  store i1 %t811, ptr %slot812, !dbg !502
  %t813 = load i1, ptr %slot36, !dbg !503
  br i1 %t813, label %or.end.256, label %or.rhs.255, !dbg !503
or.rhs.255:
  %t814 = load i1, ptr %slot812, !dbg !503
  %t815 = xor i1 %t814, true, !dbg !503
  br label %or.end.256, !dbg !503
or.end.256:
  %t816 = phi i1 [ true, %or.end.253 ], [ %t815, %or.rhs.255 ], !dbg !503
  br i1 %t816, label %if.then.257, label %if.else.258, !dbg !503
if.then.257:
  call void @lua_pushvalue(ptr %L, i32 2), !dbg !504
  %t817 = call i32 @nupp.wrap.u32(double 0x4008000000000000), !dbg !504
  %t818 = uitofp i32 %t817 to double, !dbg !504
  call void @lua_pushnumber(ptr %L, double %t818), !dbg !504
  %t819 = load i32, ptr %slot615, !dbg !504
  %t820 = add i32 %t819, 1, !dbg !504
  %t821 = uitofp i32 %t820 to double, !dbg !504
  call void @lua_pushnumber(ptr %L, double %t821), !dbg !504
  ret i32 3, !dbg !504
if.else.258:
  br label %if.end.254, !dbg !504
if.end.254:
  br label %if.end.233, !dbg !504
if.else.249:
  %t822 = load i1, ptr %slot36, !dbg !504
  %t823 = xor i1 %t822, true, !dbg !504
  br i1 %t823, label %if.then.259, label %if.else.260, !dbg !504
if.then.259:
  %t824 = load i32, ptr %slot35, !dbg !505
  %t825 = load i32, ptr %slot615, !dbg !505
  %t826 = getelementptr inbounds { ptr, i32, i32, i32, i32, [32 x i32] }, ptr %slot27, i32 0, i32 2, !dbg !505
  %t827 = load i32, ptr %t826, !dbg !505
  %t828 = getelementptr inbounds { ptr, i32, i32, i32, i32, [32 x i32] }, ptr %slot27, i32 0, i32 1, !dbg !505
  %t829 = load i32, ptr %t828, !dbg !505
  %t830 = icmp ugt i32 %t824, %t827, !dbg !505
  %t831 = icmp uge i32 %t824, %t829, !dbg !505
  %t832 = or i1 %t830, %t831, !dbg !505
  br i1 %t832, label %lua.raise.261, label %lua.ok.262, !prof !7, !dbg !505
lua.raise.261:
  %t833 = getelementptr inbounds ptr, ptr %t1, i64 11, !dbg !505
  %rt.raise.834 = load ptr, ptr %t833, !invariant.load !8, !dbg !505
  call void %rt.raise.834(ptr %L, i64 8) nomerge, !dbg !505
  unreachable, !dbg !505
lua.ok.262:
  %t835 = icmp eq i32 %t824, %t827, !dbg !505
  %t836 = add i32 %t827, 1, !dbg !505
  %t837 = select i1 %t835, i32 %t836, i32 %t827, !dbg !505
  store i32 %t837, ptr %t826, !dbg !505
  %t838 = getelementptr inbounds { ptr, i32, i32, i32, i32, [32 x i32] }, ptr %slot27, i32 0, i32 0, !dbg !505
  %t839 = load ptr, ptr %t838, !dbg !505
  %t840 = zext i32 %t824 to i64, !dbg !505
  %t841 = getelementptr inbounds i32, ptr %t839, i64 %t840, !dbg !505
  store i32 %t825, ptr %t841, !dbg !505
  %t842 = load i32, ptr %slot35, !dbg !506
  %t843 = add i32 %t842, 1, !dbg !506
  store i32 %t843, ptr %slot35, !dbg !506
  br label %if.end.233, !dbg !506
if.else.260:
  br label %if.end.233, !dbg !506
if.end.233:
  store i1 false, ptr %slot39, !dbg !507
  store i1 false, ptr %slot38, !dbg !508
  br label %if.end.171, !dbg !508
if.end.171:
  br label %if.end.161, !dbg !508
if.else.163:
  br label %if.end.161, !dbg !508
if.end.161:
  br label %while.head.158, !dbg !508
while.end.160:
  %t844 = load i32, ptr %slot33, !dbg !509
  %t845 = load i32, ptr %slot70, !dbg !509
  %t846 = add i32 %t844, %t845, !dbg !509
  store i32 %t846, ptr %slot33, !dbg !509
  br label %while.head.14, !dbg !509
while.end.16:
  br label %cursors.done.13, !dbg !509
cursors.narrow.12:
  br label %while.head.263, !dbg !509
while.head.263:
  %t847 = load i32, ptr %slot33, !dbg !509
  %t848 = load i32, ptr %slot20, !dbg !509
  %t849 = icmp ult i32 %t847, %t848, !dbg !509
  br i1 %t849, label %or.end.267, label %or.rhs.266, !dbg !509
or.rhs.266:
  %t850 = load i1, ptr %slot49, !dbg !509
  %t851 = xor i1 %t850, true, !dbg !509
  br label %or.end.267, !dbg !509
or.end.267:
  %t852 = phi i1 [ true, %while.head.263 ], [ %t851, %or.rhs.266 ], !dbg !509
  br i1 %t852, label %while.body.264, label %while.end.265, !dbg !509
while.body.264:
  %t853 = call i64 @llvm.fptosi.sat.i64.f64(double 0x0000000000000000), !dbg !381
  %t854 = call i64 @llvm.fptoui.sat.i64.f64(double 0x0000000000000000), !dbg !381
  %t855 = fcmp olt double 0x0000000000000000, 0.0, !dbg !381
  %t856 = select i1 %t855, i64 %t853, i64 %t854, !dbg !381
  store i64 %t856, ptr %slot68, !dbg !381
  %t857 = call i32 @nupp.wrap.u32(double 0x0000000000000000), !dbg !382
  store i32 %t857, ptr %slot70, !dbg !382
  br i1 true, label %if.then.269, label %if.else.270, !dbg !383
if.then.269:
  %t858 = load i1, ptr %slot56, !dbg !384
  %t859 = xor i1 %t858, true, !dbg !384
  br i1 %t859, label %and.rhs.272, label %and.end.273, !dbg !384
and.rhs.272:
  %t860 = load i32, ptr %slot33, !dbg !384
  %t861 = zext i32 %t860 to i64, !dbg !384
  %t862 = zext i32 16 to i64, !dbg !384
  %t863 = add i64 %t861, %t862, !dbg !384
  %t864 = load i32, ptr %slot20, !dbg !384
  %t865 = zext i32 %t864 to i64, !dbg !384
  %t866 = icmp ule i64 %t863, %t865, !dbg !384
  br label %and.end.273, !dbg !384
and.end.273:
  %t867 = phi i1 [ false, %if.then.269 ], [ %t866, %and.rhs.272 ], !dbg !384
  br i1 %t867, label %if.then.274, label %if.else.275, !dbg !384
if.then.274:
  %t868 = load i32, ptr %slot33, !dbg !385
  %t869 = zext i32 %t868 to i64, !dbg !385
  %t870 = add nuw i64 %t869, 16, !dbg !385
  %t871 = icmp ule i64 %t870, 4294967295, !dbg !385
  %t872 = add nuw i64 %t869, 0, !dbg !385
  %t873 = getelementptr inbounds nuw i8, ptr %t14, i64 %t872, !dbg !385
  br i1 %t871, label %simd.yes.276, label %simd.no.277, !dbg !385
simd.yes.276:
  %t874 = load <16 x i8>, ptr %t873, align 1, !dbg !385
  br label %simd.join.278, !dbg !385
simd.no.277:
  %t875 = load i32, ptr %slot33, !dbg !385
  %t876 = add i32 %t875, 1, !dbg !385
  %t877 = zext i32 %t876 to i64, !dbg !385
  %t878 = icmp ne i64 %t877, 0, !dbg !385
  %t879 = sub i64 %t877, 1, !dbg !385
  %t880 = select i1 %t878, i64 %t879, i64 -1, !dbg !385
  %t881 = icmp ult i64 %t880, %t15, !dbg !385
  %t882 = sub i64 %t15, %t880, !dbg !385
  %t883 = icmp ult i64 %t882, 16, !dbg !385
  %t884 = select i1 %t883, i64 %t882, i64 16, !dbg !385
  %t885 = select i1 %t881, i64 %t884, i64 0, !dbg !385
  %t886 = trunc i64 %t885 to i32, !dbg !385
  %t887 = select i1 %t881, i64 %t880, i64 0, !dbg !385
  %t888 = getelementptr inbounds i8, ptr %t14, i64 %t887, !dbg !385
  %t889 = icmp eq i32 %t886, 16, !dbg !385
  br i1 %t889, label %simd.yes.279, label %simd.no.280, !dbg !385
simd.yes.279:
  %t890 = load <16 x i8>, ptr %t888, align 1, !dbg !385
  br label %simd.join.281, !dbg !385
simd.no.280:
  switch i32 %t886, label %tail.done.298 [ i32 1, label %tail.lane.282 i32 2, label %tail.lane.283 i32 3, label %tail.lane.284 i32 4, label %tail.lane.285 i32 5, label %tail.lane.286 i32 6, label %tail.lane.287 i32 7, label %tail.lane.288 i32 8, label %tail.lane.289 i32 9, label %tail.lane.290 i32 10, label %tail.lane.291 i32 11, label %tail.lane.292 i32 12, label %tail.lane.293 i32 13, label %tail.lane.294 i32 14, label %tail.lane.295 i32 15, label %tail.lane.296 i32 16, label %tail.lane.297 ], !dbg !385
tail.lane.297:
  %t891 = getelementptr inbounds i8, ptr %t888, i64 15, !dbg !385
  %t892 = load i8, ptr %t891, align 1, !dbg !385
  %t893 = insertelement <16 x i8> zeroinitializer, i8 %t892, i32 15, !dbg !385
  br label %tail.lane.296, !dbg !385
tail.lane.296:
  %t894 = phi <16 x i8> [ zeroinitializer, %simd.no.280 ], [ %t893, %tail.lane.297 ], !dbg !385
  %t895 = getelementptr inbounds i8, ptr %t888, i64 14, !dbg !385
  %t896 = load i8, ptr %t895, align 1, !dbg !385
  %t897 = insertelement <16 x i8> %t894, i8 %t896, i32 14, !dbg !385
  br label %tail.lane.295, !dbg !385
tail.lane.295:
  %t898 = phi <16 x i8> [ zeroinitializer, %simd.no.280 ], [ %t897, %tail.lane.296 ], !dbg !385
  %t899 = getelementptr inbounds i8, ptr %t888, i64 13, !dbg !385
  %t900 = load i8, ptr %t899, align 1, !dbg !385
  %t901 = insertelement <16 x i8> %t898, i8 %t900, i32 13, !dbg !385
  br label %tail.lane.294, !dbg !385
tail.lane.294:
  %t902 = phi <16 x i8> [ zeroinitializer, %simd.no.280 ], [ %t901, %tail.lane.295 ], !dbg !385
  %t903 = getelementptr inbounds i8, ptr %t888, i64 12, !dbg !385
  %t904 = load i8, ptr %t903, align 1, !dbg !385
  %t905 = insertelement <16 x i8> %t902, i8 %t904, i32 12, !dbg !385
  br label %tail.lane.293, !dbg !385
tail.lane.293:
  %t906 = phi <16 x i8> [ zeroinitializer, %simd.no.280 ], [ %t905, %tail.lane.294 ], !dbg !385
  %t907 = getelementptr inbounds i8, ptr %t888, i64 11, !dbg !385
  %t908 = load i8, ptr %t907, align 1, !dbg !385
  %t909 = insertelement <16 x i8> %t906, i8 %t908, i32 11, !dbg !385
  br label %tail.lane.292, !dbg !385
tail.lane.292:
  %t910 = phi <16 x i8> [ zeroinitializer, %simd.no.280 ], [ %t909, %tail.lane.293 ], !dbg !385
  %t911 = getelementptr inbounds i8, ptr %t888, i64 10, !dbg !385
  %t912 = load i8, ptr %t911, align 1, !dbg !385
  %t913 = insertelement <16 x i8> %t910, i8 %t912, i32 10, !dbg !385
  br label %tail.lane.291, !dbg !385
tail.lane.291:
  %t914 = phi <16 x i8> [ zeroinitializer, %simd.no.280 ], [ %t913, %tail.lane.292 ], !dbg !385
  %t915 = getelementptr inbounds i8, ptr %t888, i64 9, !dbg !385
  %t916 = load i8, ptr %t915, align 1, !dbg !385
  %t917 = insertelement <16 x i8> %t914, i8 %t916, i32 9, !dbg !385
  br label %tail.lane.290, !dbg !385
tail.lane.290:
  %t918 = phi <16 x i8> [ zeroinitializer, %simd.no.280 ], [ %t917, %tail.lane.291 ], !dbg !385
  %t919 = getelementptr inbounds i8, ptr %t888, i64 8, !dbg !385
  %t920 = load i8, ptr %t919, align 1, !dbg !385
  %t921 = insertelement <16 x i8> %t918, i8 %t920, i32 8, !dbg !385
  br label %tail.lane.289, !dbg !385
tail.lane.289:
  %t922 = phi <16 x i8> [ zeroinitializer, %simd.no.280 ], [ %t921, %tail.lane.290 ], !dbg !385
  %t923 = getelementptr inbounds i8, ptr %t888, i64 7, !dbg !385
  %t924 = load i8, ptr %t923, align 1, !dbg !385
  %t925 = insertelement <16 x i8> %t922, i8 %t924, i32 7, !dbg !385
  br label %tail.lane.288, !dbg !385
tail.lane.288:
  %t926 = phi <16 x i8> [ zeroinitializer, %simd.no.280 ], [ %t925, %tail.lane.289 ], !dbg !385
  %t927 = getelementptr inbounds i8, ptr %t888, i64 6, !dbg !385
  %t928 = load i8, ptr %t927, align 1, !dbg !385
  %t929 = insertelement <16 x i8> %t926, i8 %t928, i32 6, !dbg !385
  br label %tail.lane.287, !dbg !385
tail.lane.287:
  %t930 = phi <16 x i8> [ zeroinitializer, %simd.no.280 ], [ %t929, %tail.lane.288 ], !dbg !385
  %t931 = getelementptr inbounds i8, ptr %t888, i64 5, !dbg !385
  %t932 = load i8, ptr %t931, align 1, !dbg !385
  %t933 = insertelement <16 x i8> %t930, i8 %t932, i32 5, !dbg !385
  br label %tail.lane.286, !dbg !385
tail.lane.286:
  %t934 = phi <16 x i8> [ zeroinitializer, %simd.no.280 ], [ %t933, %tail.lane.287 ], !dbg !385
  %t935 = getelementptr inbounds i8, ptr %t888, i64 4, !dbg !385
  %t936 = load i8, ptr %t935, align 1, !dbg !385
  %t937 = insertelement <16 x i8> %t934, i8 %t936, i32 4, !dbg !385
  br label %tail.lane.285, !dbg !385
tail.lane.285:
  %t938 = phi <16 x i8> [ zeroinitializer, %simd.no.280 ], [ %t937, %tail.lane.286 ], !dbg !385
  %t939 = getelementptr inbounds i8, ptr %t888, i64 3, !dbg !385
  %t940 = load i8, ptr %t939, align 1, !dbg !385
  %t941 = insertelement <16 x i8> %t938, i8 %t940, i32 3, !dbg !385
  br label %tail.lane.284, !dbg !385
tail.lane.284:
  %t942 = phi <16 x i8> [ zeroinitializer, %simd.no.280 ], [ %t941, %tail.lane.285 ], !dbg !385
  %t943 = getelementptr inbounds i8, ptr %t888, i64 2, !dbg !385
  %t944 = load i8, ptr %t943, align 1, !dbg !385
  %t945 = insertelement <16 x i8> %t942, i8 %t944, i32 2, !dbg !385
  br label %tail.lane.283, !dbg !385
tail.lane.283:
  %t946 = phi <16 x i8> [ zeroinitializer, %simd.no.280 ], [ %t945, %tail.lane.284 ], !dbg !385
  %t947 = getelementptr inbounds i8, ptr %t888, i64 1, !dbg !385
  %t948 = load i8, ptr %t947, align 1, !dbg !385
  %t949 = insertelement <16 x i8> %t946, i8 %t948, i32 1, !dbg !385
  br label %tail.lane.282, !dbg !385
tail.lane.282:
  %t950 = phi <16 x i8> [ zeroinitializer, %simd.no.280 ], [ %t949, %tail.lane.283 ], !dbg !385
  %t951 = getelementptr inbounds i8, ptr %t888, i64 0, !dbg !385
  %t952 = load i8, ptr %t951, align 1, !dbg !385
  %t953 = insertelement <16 x i8> %t950, i8 %t952, i32 0, !dbg !385
  br label %tail.done.298, !dbg !385
tail.done.298:
  %t954 = phi <16 x i8> [ zeroinitializer, %simd.no.280 ], [ %t953, %tail.lane.282 ], !dbg !385
  br label %simd.join.281, !dbg !385
simd.join.281:
  %t955 = phi <16 x i8> [ %t890, %simd.yes.279 ], [ %t954, %tail.done.298 ], !dbg !385
  br label %simd.join.278, !dbg !385
simd.join.278:
  %t956 = phi <16 x i8> [ %t874, %simd.yes.276 ], [ %t955, %simd.join.281 ], !dbg !385
  store <16 x i8> %t956, ptr %slot168, !dbg !385
  %t957 = load <16 x i8>, ptr %slot168, !dbg !386
  %t958 = call i32 @nupp.wrap.u32(double 0x405EC00000000000), !dbg !386
  %t959 = trunc i32 %t958 to i8, !dbg !386
  %t960 = insertelement <16 x i8> poison, i8 %t959, i64 0, !dbg !386
  %t961 = shufflevector <16 x i8> %t960, <16 x i8> poison, <16 x i32> zeroinitializer, !dbg !386
  %t962 = icmp eq <16 x i8> %t957, %t961, !dbg !386
  %t963 = load <16 x i8>, ptr %slot168, !dbg !386
  %t964 = call i32 @nupp.wrap.u32(double 0x405F400000000000), !dbg !386
  %t965 = trunc i32 %t964 to i8, !dbg !386
  %t966 = insertelement <16 x i8> poison, i8 %t965, i64 0, !dbg !386
  %t967 = shufflevector <16 x i8> %t966, <16 x i8> poison, <16 x i32> zeroinitializer, !dbg !386
  %t968 = icmp eq <16 x i8> %t963, %t967, !dbg !386
  %t969 = or <16 x i1> %t962, %t968, !dbg !386
  %t970 = load <16 x i8>, ptr %slot168, !dbg !386
  %t971 = call i32 @nupp.wrap.u32(double 0x4056C00000000000), !dbg !386
  %t972 = trunc i32 %t971 to i8, !dbg !386
  %t973 = insertelement <16 x i8> poison, i8 %t972, i64 0, !dbg !386
  %t974 = shufflevector <16 x i8> %t973, <16 x i8> poison, <16 x i32> zeroinitializer, !dbg !386
  %t975 = icmp eq <16 x i8> %t970, %t974, !dbg !386
  %t976 = or <16 x i1> %t969, %t975, !dbg !386
  %t977 = load <16 x i8>, ptr %slot168, !dbg !386
  %t978 = call i32 @nupp.wrap.u32(double 0x4057400000000000), !dbg !386
  %t979 = trunc i32 %t978 to i8, !dbg !386
  %t980 = insertelement <16 x i8> poison, i8 %t979, i64 0, !dbg !386
  %t981 = shufflevector <16 x i8> %t980, <16 x i8> poison, <16 x i32> zeroinitializer, !dbg !386
  %t982 = icmp eq <16 x i8> %t977, %t981, !dbg !386
  %t983 = or <16 x i1> %t976, %t982, !dbg !386
  store <16 x i1> %t983, ptr %slot196, !dbg !386
  %t984 = load <16 x i8>, ptr %slot168, !dbg !387
  %t985 = call i32 @nupp.wrap.u32(double 0x404D000000000000), !dbg !387
  %t986 = trunc i32 %t985 to i8, !dbg !387
  %t987 = insertelement <16 x i8> poison, i8 %t986, i64 0, !dbg !387
  %t988 = shufflevector <16 x i8> %t987, <16 x i8> poison, <16 x i32> zeroinitializer, !dbg !387
  %t989 = icmp eq <16 x i8> %t984, %t988, !dbg !387
  %t990 = load <16 x i8>, ptr %slot168, !dbg !387
  %t991 = call i32 @nupp.wrap.u32(double 0x4046000000000000), !dbg !387
  %t992 = trunc i32 %t991 to i8, !dbg !387
  %t993 = insertelement <16 x i8> poison, i8 %t992, i64 0, !dbg !387
  %t994 = shufflevector <16 x i8> %t993, <16 x i8> poison, <16 x i32> zeroinitializer, !dbg !387
  %t995 = icmp eq <16 x i8> %t990, %t994, !dbg !387
  %t996 = or <16 x i1> %t989, %t995, !dbg !387
  store <16 x i1> %t996, ptr %slot210, !dbg !387
  %t997 = load <16 x i8>, ptr %slot168, !dbg !388
  %t998 = call i32 @nupp.wrap.u32(double 0x4041000000000000), !dbg !388
  %t999 = trunc i32 %t998 to i8, !dbg !388
  %t1000 = insertelement <16 x i8> poison, i8 %t999, i64 0, !dbg !388
  %t1001 = shufflevector <16 x i8> %t1000, <16 x i8> poison, <16 x i32> zeroinitializer, !dbg !388
  %t1002 = icmp eq <16 x i8> %t997, %t1001, !dbg !388
  %t1003 = load <16 x i8>, ptr %slot168, !dbg !388
  %t1004 = call i32 @nupp.wrap.u32(double 0x4057000000000000), !dbg !388
  %t1005 = trunc i32 %t1004 to i8, !dbg !388
  %t1006 = insertelement <16 x i8> poison, i8 %t1005, i64 0, !dbg !388
  %t1007 = shufflevector <16 x i8> %t1006, <16 x i8> poison, <16 x i32> zeroinitializer, !dbg !388
  %t1008 = icmp eq <16 x i8> %t1003, %t1007, !dbg !388
  %t1009 = or <16 x i1> %t1002, %t1008, !dbg !388
  store <16 x i1> %t1009, ptr %slot224, !dbg !388
  %t1010 = load <16 x i1>, ptr %slot196, !dbg !389
  %t1011 = load <16 x i1>, ptr %slot210, !dbg !389
  %t1012 = or <16 x i1> %t1010, %t1011, !dbg !389
  %t1013 = load <16 x i1>, ptr %slot224, !dbg !389
  %t1014 = or <16 x i1> %t1012, %t1013, !dbg !389
  %t1015 = load <16 x i8>, ptr %slot168, !dbg !389
  %t1016 = call i32 @nupp.wrap.u32(double 0x4040000000000000), !dbg !389
  %t1017 = trunc i32 %t1016 to i8, !dbg !389
  %t1018 = insertelement <16 x i8> poison, i8 %t1017, i64 0, !dbg !389
  %t1019 = shufflevector <16 x i8> %t1018, <16 x i8> poison, <16 x i32> zeroinitializer, !dbg !389
  %t1020 = icmp ult <16 x i8> %t1015, %t1019, !dbg !389
  %t1021 = or <16 x i1> %t1014, %t1020, !dbg !389
  store <16 x i1> %t1021, ptr %slot237, !dbg !389
  store i1 false, ptr %slot238, !dbg !390
  %t1022 = load i1, ptr %slot50, !dbg !391
  br i1 %t1022, label %if.then.300, label %if.else.301, !dbg !391
if.then.300:
  %t1023 = load <16 x i1>, ptr %slot237, !dbg !392
  %t1024 = bitcast <16 x i1> %t1023 to i16, !dbg !392
  %t1025 = zext i16 %t1024 to i64, !dbg !392
  store i64 %t1025, ptr %slot68, !dbg !392
  store i1 true, ptr %slot238, !dbg !393
  br label %if.end.299, !dbg !393
if.else.301:
  %t1026 = load <16 x i8>, ptr %slot168, !dbg !394
  %t1027 = call i32 @nupp.wrap.u32(double 0x4060000000000000), !dbg !394
  %t1028 = trunc i32 %t1027 to i8, !dbg !394
  %t1029 = insertelement <16 x i8> poison, i8 %t1028, i64 0, !dbg !394
  %t1030 = shufflevector <16 x i8> %t1029, <16 x i8> poison, <16 x i32> zeroinitializer, !dbg !394
  %t1031 = icmp uge <16 x i8> %t1026, %t1030, !dbg !394
  store <16 x i1> %t1031, ptr %slot249, !dbg !394
  %t1032 = load <16 x i1>, ptr %slot237, !dbg !395
  %t1033 = load <16 x i1>, ptr %slot249, !dbg !395
  %t1034 = or <16 x i1> %t1032, %t1033, !dbg !395
  %t1035 = bitcast <16 x i1> %t1034 to i16, !dbg !395
  %t1036 = zext i16 %t1035 to i64, !dbg !395
  store i64 %t1036, ptr %slot68, !dbg !395
  %t1037 = load i64, ptr %slot68, !dbg !396
  %t1038 = call i64 @llvm.fptosi.sat.i64.f64(double 0x0000000000000000), !dbg !396
  %t1039 = call i64 @llvm.fptoui.sat.i64.f64(double 0x0000000000000000), !dbg !396
  %t1040 = fcmp olt double 0x0000000000000000, 0.0, !dbg !396
  %t1041 = select i1 %t1040, i64 %t1038, i64 %t1039, !dbg !396
  %t1042 = icmp ne i64 %t1037, %t1041, !dbg !396
  br i1 %t1042, label %if.then.303, label %if.else.304, !dbg !396
if.then.303:
  %t1043 = load <16 x i1>, ptr %slot249, !dbg !397
  %t1044 = sext <16 x i1> %t1043 to <16 x i8>, !dbg !397
  %t1045 = call <16 x i8> asm "", "=w,0"(<16 x i8> %t1044), !dbg !397
  %t1046 = bitcast <16 x i8> %t1045 to <4 x i32>, !dbg !397
  %t1047 = shufflevector <4 x i32> %t1046, <4 x i32> poison, <4 x i32> <i32 0, i32 1, i32 2, i32 3>, !dbg !397
  %t1048 = call <4 x i32> @llvm.aarch64.neon.umaxp.v4i32(<4 x i32> %t1047, <4 x i32> %t1047), !dbg !397
  %t1049 = bitcast <4 x i32> %t1048 to <2 x i64>, !dbg !397
  %t1050 = extractelement <2 x i64> %t1049, i32 0, !dbg !397
  %t1051 = icmp ne i64 %t1050, 0, !dbg !397
  store i1 %t1051, ptr %slot238, !dbg !397
  %t1052 = load i1, ptr %slot238, !dbg !398
  br i1 %t1052, label %if.then.306, label %if.else.307, !dbg !398
if.then.306:
  %t1053 = load <16 x i1>, ptr %slot237, !dbg !399
  %t1054 = bitcast <16 x i1> %t1053 to i16, !dbg !399
  %t1055 = zext i16 %t1054 to i64, !dbg !399
  store i64 %t1055, ptr %slot68, !dbg !399
  br label %if.end.305, !dbg !399
if.else.307:
  br label %if.end.305, !dbg !399
if.end.305:
  br label %if.end.302, !dbg !399
if.else.304:
  br label %if.end.302, !dbg !399
if.end.302:
  br label %if.end.299, !dbg !399
if.end.299:
  %t1056 = load i1, ptr %slot238, !dbg !400
  br i1 %t1056, label %if.then.309, label %if.else.310, !dbg !400
if.then.309:
  %t1057 = load i32, ptr %slot33, !dbg !401
  %t1058 = sub i32 %t1057, 16, !dbg !401
  %t1059 = add i32 %t1058, 1, !dbg !401
  %t1060 = zext i32 %t1059 to i64, !dbg !401
  %t1061 = icmp ne i64 %t1060, 0, !dbg !401
  %t1062 = sub i64 %t1060, 1, !dbg !401
  %t1063 = select i1 %t1061, i64 %t1062, i64 -1, !dbg !401
  %t1064 = icmp ult i64 %t1063, %t15, !dbg !401
  %t1065 = sub i64 %t15, %t1063, !dbg !401
  %t1066 = icmp ult i64 %t1065, 16, !dbg !401
  %t1067 = select i1 %t1066, i64 %t1065, i64 16, !dbg !401
  %t1068 = select i1 %t1064, i64 %t1067, i64 0, !dbg !401
  %t1069 = trunc i64 %t1068 to i32, !dbg !401
  %t1070 = select i1 %t1064, i64 %t1063, i64 0, !dbg !401
  %t1071 = getelementptr inbounds i8, ptr %t14, i64 %t1070, !dbg !401
  %t1072 = icmp eq i32 %t1069, 16, !dbg !401
  br i1 %t1072, label %simd.yes.311, label %simd.no.312, !dbg !401
simd.yes.311:
  %t1073 = load <16 x i8>, ptr %t1071, align 1, !dbg !401
  br label %simd.join.313, !dbg !401
simd.no.312:
  switch i32 %t1069, label %tail.done.330 [ i32 1, label %tail.lane.314 i32 2, label %tail.lane.315 i32 3, label %tail.lane.316 i32 4, label %tail.lane.317 i32 5, label %tail.lane.318 i32 6, label %tail.lane.319 i32 7, label %tail.lane.320 i32 8, label %tail.lane.321 i32 9, label %tail.lane.322 i32 10, label %tail.lane.323 i32 11, label %tail.lane.324 i32 12, label %tail.lane.325 i32 13, label %tail.lane.326 i32 14, label %tail.lane.327 i32 15, label %tail.lane.328 i32 16, label %tail.lane.329 ], !dbg !401
tail.lane.329:
  %t1074 = getelementptr inbounds i8, ptr %t1071, i64 15, !dbg !401
  %t1075 = load i8, ptr %t1074, align 1, !dbg !401
  %t1076 = insertelement <16 x i8> zeroinitializer, i8 %t1075, i32 15, !dbg !401
  br label %tail.lane.328, !dbg !401
tail.lane.328:
  %t1077 = phi <16 x i8> [ zeroinitializer, %simd.no.312 ], [ %t1076, %tail.lane.329 ], !dbg !401
  %t1078 = getelementptr inbounds i8, ptr %t1071, i64 14, !dbg !401
  %t1079 = load i8, ptr %t1078, align 1, !dbg !401
  %t1080 = insertelement <16 x i8> %t1077, i8 %t1079, i32 14, !dbg !401
  br label %tail.lane.327, !dbg !401
tail.lane.327:
  %t1081 = phi <16 x i8> [ zeroinitializer, %simd.no.312 ], [ %t1080, %tail.lane.328 ], !dbg !401
  %t1082 = getelementptr inbounds i8, ptr %t1071, i64 13, !dbg !401
  %t1083 = load i8, ptr %t1082, align 1, !dbg !401
  %t1084 = insertelement <16 x i8> %t1081, i8 %t1083, i32 13, !dbg !401
  br label %tail.lane.326, !dbg !401
tail.lane.326:
  %t1085 = phi <16 x i8> [ zeroinitializer, %simd.no.312 ], [ %t1084, %tail.lane.327 ], !dbg !401
  %t1086 = getelementptr inbounds i8, ptr %t1071, i64 12, !dbg !401
  %t1087 = load i8, ptr %t1086, align 1, !dbg !401
  %t1088 = insertelement <16 x i8> %t1085, i8 %t1087, i32 12, !dbg !401
  br label %tail.lane.325, !dbg !401
tail.lane.325:
  %t1089 = phi <16 x i8> [ zeroinitializer, %simd.no.312 ], [ %t1088, %tail.lane.326 ], !dbg !401
  %t1090 = getelementptr inbounds i8, ptr %t1071, i64 11, !dbg !401
  %t1091 = load i8, ptr %t1090, align 1, !dbg !401
  %t1092 = insertelement <16 x i8> %t1089, i8 %t1091, i32 11, !dbg !401
  br label %tail.lane.324, !dbg !401
tail.lane.324:
  %t1093 = phi <16 x i8> [ zeroinitializer, %simd.no.312 ], [ %t1092, %tail.lane.325 ], !dbg !401
  %t1094 = getelementptr inbounds i8, ptr %t1071, i64 10, !dbg !401
  %t1095 = load i8, ptr %t1094, align 1, !dbg !401
  %t1096 = insertelement <16 x i8> %t1093, i8 %t1095, i32 10, !dbg !401
  br label %tail.lane.323, !dbg !401
tail.lane.323:
  %t1097 = phi <16 x i8> [ zeroinitializer, %simd.no.312 ], [ %t1096, %tail.lane.324 ], !dbg !401
  %t1098 = getelementptr inbounds i8, ptr %t1071, i64 9, !dbg !401
  %t1099 = load i8, ptr %t1098, align 1, !dbg !401
  %t1100 = insertelement <16 x i8> %t1097, i8 %t1099, i32 9, !dbg !401
  br label %tail.lane.322, !dbg !401
tail.lane.322:
  %t1101 = phi <16 x i8> [ zeroinitializer, %simd.no.312 ], [ %t1100, %tail.lane.323 ], !dbg !401
  %t1102 = getelementptr inbounds i8, ptr %t1071, i64 8, !dbg !401
  %t1103 = load i8, ptr %t1102, align 1, !dbg !401
  %t1104 = insertelement <16 x i8> %t1101, i8 %t1103, i32 8, !dbg !401
  br label %tail.lane.321, !dbg !401
tail.lane.321:
  %t1105 = phi <16 x i8> [ zeroinitializer, %simd.no.312 ], [ %t1104, %tail.lane.322 ], !dbg !401
  %t1106 = getelementptr inbounds i8, ptr %t1071, i64 7, !dbg !401
  %t1107 = load i8, ptr %t1106, align 1, !dbg !401
  %t1108 = insertelement <16 x i8> %t1105, i8 %t1107, i32 7, !dbg !401
  br label %tail.lane.320, !dbg !401
tail.lane.320:
  %t1109 = phi <16 x i8> [ zeroinitializer, %simd.no.312 ], [ %t1108, %tail.lane.321 ], !dbg !401
  %t1110 = getelementptr inbounds i8, ptr %t1071, i64 6, !dbg !401
  %t1111 = load i8, ptr %t1110, align 1, !dbg !401
  %t1112 = insertelement <16 x i8> %t1109, i8 %t1111, i32 6, !dbg !401
  br label %tail.lane.319, !dbg !401
tail.lane.319:
  %t1113 = phi <16 x i8> [ zeroinitializer, %simd.no.312 ], [ %t1112, %tail.lane.320 ], !dbg !401
  %t1114 = getelementptr inbounds i8, ptr %t1071, i64 5, !dbg !401
  %t1115 = load i8, ptr %t1114, align 1, !dbg !401
  %t1116 = insertelement <16 x i8> %t1113, i8 %t1115, i32 5, !dbg !401
  br label %tail.lane.318, !dbg !401
tail.lane.318:
  %t1117 = phi <16 x i8> [ zeroinitializer, %simd.no.312 ], [ %t1116, %tail.lane.319 ], !dbg !401
  %t1118 = getelementptr inbounds i8, ptr %t1071, i64 4, !dbg !401
  %t1119 = load i8, ptr %t1118, align 1, !dbg !401
  %t1120 = insertelement <16 x i8> %t1117, i8 %t1119, i32 4, !dbg !401
  br label %tail.lane.317, !dbg !401
tail.lane.317:
  %t1121 = phi <16 x i8> [ zeroinitializer, %simd.no.312 ], [ %t1120, %tail.lane.318 ], !dbg !401
  %t1122 = getelementptr inbounds i8, ptr %t1071, i64 3, !dbg !401
  %t1123 = load i8, ptr %t1122, align 1, !dbg !401
  %t1124 = insertelement <16 x i8> %t1121, i8 %t1123, i32 3, !dbg !401
  br label %tail.lane.316, !dbg !401
tail.lane.316:
  %t1125 = phi <16 x i8> [ zeroinitializer, %simd.no.312 ], [ %t1124, %tail.lane.317 ], !dbg !401
  %t1126 = getelementptr inbounds i8, ptr %t1071, i64 2, !dbg !401
  %t1127 = load i8, ptr %t1126, align 1, !dbg !401
  %t1128 = insertelement <16 x i8> %t1125, i8 %t1127, i32 2, !dbg !401
  br label %tail.lane.315, !dbg !401
tail.lane.315:
  %t1129 = phi <16 x i8> [ zeroinitializer, %simd.no.312 ], [ %t1128, %tail.lane.316 ], !dbg !401
  %t1130 = getelementptr inbounds i8, ptr %t1071, i64 1, !dbg !401
  %t1131 = load i8, ptr %t1130, align 1, !dbg !401
  %t1132 = insertelement <16 x i8> %t1129, i8 %t1131, i32 1, !dbg !401
  br label %tail.lane.314, !dbg !401
tail.lane.314:
  %t1133 = phi <16 x i8> [ zeroinitializer, %simd.no.312 ], [ %t1132, %tail.lane.315 ], !dbg !401
  %t1134 = getelementptr inbounds i8, ptr %t1071, i64 0, !dbg !401
  %t1135 = load i8, ptr %t1134, align 1, !dbg !401
  %t1136 = insertelement <16 x i8> %t1133, i8 %t1135, i32 0, !dbg !401
  br label %tail.done.330, !dbg !401
tail.done.330:
  %t1137 = phi <16 x i8> [ zeroinitializer, %simd.no.312 ], [ %t1136, %tail.lane.314 ], !dbg !401
  br label %simd.join.313, !dbg !401
simd.join.313:
  %t1138 = phi <16 x i8> [ %t1073, %simd.yes.311 ], [ %t1137, %tail.done.330 ], !dbg !401
  store <16 x i8> %t1138, ptr %slot357, !dbg !401
  %t1139 = load <16 x i8>, ptr %slot357, !dbg !402
  %t1140 = load <16 x i8>, ptr %slot168, !dbg !402
  %t1141 = shufflevector <16 x i8> %t1139, <16 x i8> %t1140, <16 x i32> <i32 15, i32 16, i32 17, i32 18, i32 19, i32 20, i32 21, i32 22, i32 23, i32 24, i32 25, i32 26, i32 27, i32 28, i32 29, i32 30>, !dbg !402
  store <16 x i8> %t1141, ptr %slot361, !dbg !402
  %t1142 = load <16 x i8>, ptr %slot357, !dbg !403
  %t1143 = load <16 x i8>, ptr %slot168, !dbg !403
  %t1144 = shufflevector <16 x i8> %t1142, <16 x i8> %t1143, <16 x i32> <i32 14, i32 15, i32 16, i32 17, i32 18, i32 19, i32 20, i32 21, i32 22, i32 23, i32 24, i32 25, i32 26, i32 27, i32 28, i32 29>, !dbg !403
  store <16 x i8> %t1144, ptr %slot365, !dbg !403
  %t1145 = load <16 x i8>, ptr %slot357, !dbg !404
  %t1146 = load <16 x i8>, ptr %slot168, !dbg !404
  %t1147 = shufflevector <16 x i8> %t1145, <16 x i8> %t1146, <16 x i32> <i32 13, i32 14, i32 15, i32 16, i32 17, i32 18, i32 19, i32 20, i32 21, i32 22, i32 23, i32 24, i32 25, i32 26, i32 27, i32 28>, !dbg !404
  store <16 x i8> %t1147, ptr %slot369, !dbg !404
  %t1148 = call i32 @nupp.wrap.u32(double 0x0000000000000000), !dbg !405
  %t1149 = trunc i32 %t1148 to i8, !dbg !405
  %t1150 = insertelement <16 x i8> poison, i8 %t1149, i64 0, !dbg !405
  %t1151 = shufflevector <16 x i8> %t1150, <16 x i8> poison, <16 x i32> zeroinitializer, !dbg !405
  store <16 x i8> %t1151, ptr %slot374, !dbg !405
  %t1152 = load <16 x i8>, ptr %slot374, !dbg !406
  %t1153 = call <16 x i8> @ks___nupp_const_decode_fused_a640dbc37ebbc1be__5f5f6e757070436f6e73745f6465636f646546757365645f61363430646263333765626263316265_helper_nibble_table(<16 x i8> %t1152, i32 2, i32 2, i32 2, i32 2, i32 2, i32 2, i32 2, i32 2, i32 128, i32 128, i32 128, i32 128, i32 33, i32 1, i32 21, i32 73), !dbg !406
  store <16 x i8> %t1153, ptr %slot377, !dbg !406
  %t1154 = load <16 x i8>, ptr %slot374, !dbg !407
  %t1155 = call <16 x i8> @ks___nupp_const_decode_fused_a640dbc37ebbc1be__5f5f6e757070436f6e73745f6465636f646546757365645f61363430646263333765626263316265_helper_nibble_table(<16 x i8> %t1154, i32 231, i32 163, i32 131, i32 131, i32 139, i32 203, i32 203, i32 203, i32 203, i32 203, i32 203, i32 203, i32 203, i32 219, i32 203, i32 203), !dbg !407
  store <16 x i8> %t1155, ptr %slot380, !dbg !407
  %t1156 = load <16 x i8>, ptr %slot374, !dbg !408
  %t1157 = call <16 x i8> @ks___nupp_const_decode_fused_a640dbc37ebbc1be__5f5f6e757070436f6e73745f6465636f646546757365645f61363430646263333765626263316265_helper_nibble_table(<16 x i8> %t1156, i32 1, i32 1, i32 1, i32 1, i32 1, i32 1, i32 1, i32 1, i32 230, i32 174, i32 186, i32 186, i32 1, i32 1, i32 1, i32 1), !dbg !408
  store <16 x i8> %t1157, ptr %slot383, !dbg !408
  %t1158 = load <16 x i8>, ptr %slot377, !dbg !409
  %t1159 = load <16 x i8>, ptr %slot361, !dbg !409
  %t1160 = call i32 @nupp.wrap.u32(double 0x4010000000000000), !dbg !409
  %t1161 = trunc i32 %t1160 to i8, !dbg !409
  %t1162 = insertelement <16 x i8> poison, i8 %t1161, i64 0, !dbg !409
  %t1163 = shufflevector <16 x i8> %t1162, <16 x i8> poison, <16 x i32> zeroinitializer, !dbg !409
  %t1164 = and <16 x i8> %t1163, splat (i8 7), !dbg !409
  %t1165 = lshr <16 x i8> %t1159, %t1164, !dbg !409
  %t1166 = call i32 @nupp.wrap.u32(double 0x3FF0000000000000), !dbg !409
  %t1167 = trunc i32 %t1166 to i8, !dbg !409
  %t1168 = insertelement <16 x i8> poison, i8 %t1167, i64 0, !dbg !409
  %t1169 = shufflevector <16 x i8> %t1168, <16 x i8> poison, <16 x i32> zeroinitializer, !dbg !409
  %t1170 = add <16 x i8> %t1165, %t1169, !dbg !409
  %t1171 = sub <16 x i8> %t1170, splat (i8 1), !dbg !409
  %t1172 = call <16 x i8> @llvm.aarch64.neon.tbl1.v16i8(<16 x i8> %t1158, <16 x i8> %t1171), !dbg !409
  %t1173 = load <16 x i8>, ptr %slot380, !dbg !409
  %t1174 = load <16 x i8>, ptr %slot361, !dbg !409
  %t1175 = call i32 @nupp.wrap.u32(double 0x402E000000000000), !dbg !409
  %t1176 = trunc i32 %t1175 to i8, !dbg !409
  %t1177 = insertelement <16 x i8> poison, i8 %t1176, i64 0, !dbg !409
  %t1178 = shufflevector <16 x i8> %t1177, <16 x i8> poison, <16 x i32> zeroinitializer, !dbg !409
  %t1179 = and <16 x i8> %t1174, %t1178, !dbg !409
  %t1180 = call i32 @nupp.wrap.u32(double 0x3FF0000000000000), !dbg !409
  %t1181 = trunc i32 %t1180 to i8, !dbg !409
  %t1182 = insertelement <16 x i8> poison, i8 %t1181, i64 0, !dbg !409
  %t1183 = shufflevector <16 x i8> %t1182, <16 x i8> poison, <16 x i32> zeroinitializer, !dbg !409
  %t1184 = add <16 x i8> %t1179, %t1183, !dbg !409
  %t1185 = sub <16 x i8> %t1184, splat (i8 1), !dbg !409
  %t1186 = call <16 x i8> @llvm.aarch64.neon.tbl1.v16i8(<16 x i8> %t1173, <16 x i8> %t1185), !dbg !409
  %t1187 = and <16 x i8> %t1172, %t1186, !dbg !409
  %t1188 = load <16 x i8>, ptr %slot383, !dbg !409
  %t1189 = load <16 x i8>, ptr %slot168, !dbg !409
  %t1190 = call i32 @nupp.wrap.u32(double 0x4010000000000000), !dbg !409
  %t1191 = trunc i32 %t1190 to i8, !dbg !409
  %t1192 = insertelement <16 x i8> poison, i8 %t1191, i64 0, !dbg !409
  %t1193 = shufflevector <16 x i8> %t1192, <16 x i8> poison, <16 x i32> zeroinitializer, !dbg !409
  %t1194 = and <16 x i8> %t1193, splat (i8 7), !dbg !409
  %t1195 = lshr <16 x i8> %t1189, %t1194, !dbg !409
  %t1196 = call i32 @nupp.wrap.u32(double 0x3FF0000000000000), !dbg !409
  %t1197 = trunc i32 %t1196 to i8, !dbg !409
  %t1198 = insertelement <16 x i8> poison, i8 %t1197, i64 0, !dbg !409
  %t1199 = shufflevector <16 x i8> %t1198, <16 x i8> poison, <16 x i32> zeroinitializer, !dbg !409
  %t1200 = add <16 x i8> %t1195, %t1199, !dbg !409
  %t1201 = sub <16 x i8> %t1200, splat (i8 1), !dbg !409
  %t1202 = call <16 x i8> @llvm.aarch64.neon.tbl1.v16i8(<16 x i8> %t1188, <16 x i8> %t1201), !dbg !409
  %t1203 = and <16 x i8> %t1187, %t1202, !dbg !409
  store <16 x i8> %t1203, ptr %slot430, !dbg !409
  %t1204 = call i32 @nupp.wrap.u32(double 0x4060000000000000), !dbg !410
  %t1205 = trunc i32 %t1204 to i8, !dbg !410
  %t1206 = insertelement <16 x i8> poison, i8 %t1205, i64 0, !dbg !410
  %t1207 = shufflevector <16 x i8> %t1206, <16 x i8> poison, <16 x i32> zeroinitializer, !dbg !410
  %t1208 = call i32 @nupp.wrap.u32(double 0x0000000000000000), !dbg !410
  %t1209 = trunc i32 %t1208 to i8, !dbg !410
  %t1210 = insertelement <16 x i8> poison, i8 %t1209, i64 0, !dbg !410
  %t1211 = shufflevector <16 x i8> %t1210, <16 x i8> poison, <16 x i32> zeroinitializer, !dbg !410
  %t1212 = load <16 x i8>, ptr %slot365, !dbg !410
  %t1213 = call i32 @nupp.wrap.u32(double 0x406C000000000000), !dbg !410
  %t1214 = trunc i32 %t1213 to i8, !dbg !410
  %t1215 = insertelement <16 x i8> poison, i8 %t1214, i64 0, !dbg !410
  %t1216 = shufflevector <16 x i8> %t1215, <16 x i8> poison, <16 x i32> zeroinitializer, !dbg !410
  %t1217 = icmp uge <16 x i8> %t1212, %t1216, !dbg !410
  %t1218 = load <16 x i8>, ptr %slot369, !dbg !410
  %t1219 = call i32 @nupp.wrap.u32(double 0x406E000000000000), !dbg !410
  %t1220 = trunc i32 %t1219 to i8, !dbg !410
  %t1221 = insertelement <16 x i8> poison, i8 %t1220, i64 0, !dbg !410
  %t1222 = shufflevector <16 x i8> %t1221, <16 x i8> poison, <16 x i32> zeroinitializer, !dbg !410
  %t1223 = icmp uge <16 x i8> %t1218, %t1222, !dbg !410
  %t1224 = or <16 x i1> %t1217, %t1223, !dbg !410
  %t1225 = select <16 x i1> %t1224, <16 x i8> %t1207, <16 x i8> %t1211, !dbg !410
  store <16 x i8> %t1225, ptr %slot453, !dbg !410
  %t1226 = load <16 x i8>, ptr %slot430, !dbg !411
  %t1227 = load <16 x i8>, ptr %slot453, !dbg !411
  %t1228 = xor <16 x i8> %t1226, %t1227, !dbg !411
  %t1229 = call i32 @nupp.wrap.u32(double 0x0000000000000000), !dbg !411
  %t1230 = trunc i32 %t1229 to i8, !dbg !411
  %t1231 = zext i8 %t1230 to i32, !dbg !411
  %t1232 = call i32 @llvm.aarch64.neon.umaxv.i32.v16i8(<16 x i8> %t1228), !dbg !411
  %t1233 = trunc i32 %t1232 to i8, !dbg !411
  %t1234 = zext i8 %t1233 to i32, !dbg !411
  %t1235 = icmp ne i32 %t1234, 0, !dbg !411
  br i1 %t1235, label %if.then.332, label %if.else.333, !dbg !411
if.then.332:
  store i1 true, ptr %slot56, !dbg !412
  br label %if.end.331, !dbg !412
if.else.333:
  %t1236 = load <16 x i8>, ptr %slot168, !dbg !413
  %t1237 = load <16 x i8>, ptr %slot168, !dbg !413
  %t1238 = shufflevector <16 x i8> %t1236, <16 x i8> %t1237, <16 x i32> <i32 15, i32 16, i32 17, i32 18, i32 19, i32 20, i32 21, i32 22, i32 23, i32 24, i32 25, i32 26, i32 27, i32 28, i32 29, i32 30>, !dbg !413
  %t1239 = extractelement <16 x i8> %t1238, i32 0, !dbg !413
  %t1240 = zext i8 %t1239 to i32, !dbg !413
  %t1241 = icmp uge i32 %t1240, 128, !dbg !413
  store i1 %t1241, ptr %slot50, !dbg !413
  br label %if.end.331, !dbg !413
if.end.331:
  br label %if.end.308, !dbg !413
if.else.310:
  store i1 false, ptr %slot50, !dbg !414
  br label %if.end.308, !dbg !414
if.end.308:
  %t1242 = load i1, ptr %slot56, !dbg !415
  %t1243 = xor i1 %t1242, true, !dbg !415
  br i1 %t1243, label %if.then.335, label %if.else.336, !dbg !415
if.then.335:
  store i32 16, ptr %slot70, !dbg !416
  br label %if.end.334, !dbg !416
if.else.336:
  %t1244 = call i64 @llvm.fptosi.sat.i64.f64(double 0x0000000000000000), !dbg !417
  %t1245 = call i64 @llvm.fptoui.sat.i64.f64(double 0x0000000000000000), !dbg !417
  %t1246 = fcmp olt double 0x0000000000000000, 0.0, !dbg !417
  %t1247 = select i1 %t1246, i64 %t1244, i64 %t1245, !dbg !417
  store i64 %t1247, ptr %slot68, !dbg !417
  br label %if.end.334, !dbg !417
if.end.334:
  br label %if.end.271, !dbg !417
if.else.275:
  br label %if.end.271, !dbg !417
if.end.271:
  br label %if.end.268, !dbg !417
if.else.270:
  br label %if.end.268, !dbg !417
if.end.268:
  %t1248 = load i32, ptr %slot70, !dbg !418
  %t1249 = icmp eq i32 %t1248, 0, !dbg !418
  br i1 %t1249, label %and.rhs.338, label %and.end.339, !dbg !418
and.rhs.338:
  %t1250 = load i1, ptr %slot49, !dbg !418
  %t1251 = xor i1 %t1250, true, !dbg !418
  br label %and.end.339, !dbg !418
and.end.339:
  %t1252 = phi i1 [ false, %if.end.268 ], [ %t1251, %and.rhs.338 ], !dbg !418
  br i1 %t1252, label %if.then.340, label %if.else.341, !dbg !418
if.then.340:
  store i1 true, ptr %slot49, !dbg !419
  %t1253 = call i32 @nupp.wrap.u32(double 0x3FF0000000000000), !dbg !420
  store i32 %t1253, ptr %slot482, !dbg !420
  store i1 true, ptr %slot483, !dbg !421
  br label %while.head.342, !dbg !422
while.head.342:
  %t1254 = load i1, ptr %slot483, !dbg !422
  br i1 %t1254, label %and.rhs.345, label %and.end.346, !dbg !422
and.rhs.345:
  %t1255 = load i32, ptr %slot482, !dbg !422
  %t1256 = icmp ule i32 %t1255, 3, !dbg !422
  br label %and.end.346, !dbg !422
and.end.346:
  %t1257 = phi i1 [ false, %while.head.342 ], [ %t1256, %and.rhs.345 ], !dbg !422
  br i1 %t1257, label %and.rhs.347, label %and.end.348, !dbg !422
and.rhs.347:
  %t1258 = load i32, ptr %slot482, !dbg !422
  %t1259 = load i32, ptr %slot33, !dbg !422
  %t1260 = icmp ule i32 %t1258, %t1259, !dbg !422
  br label %and.end.348, !dbg !422
and.end.348:
  %t1261 = phi i1 [ false, %and.end.346 ], [ %t1260, %and.rhs.347 ], !dbg !422
  br i1 %t1261, label %while.body.343, label %while.end.344, !dbg !422
while.body.343:
  %t1262 = load i32, ptr %slot33, !dbg !423
  %t1263 = load i32, ptr %slot482, !dbg !423
  %t1264 = sub i32 %t1262, %t1263, !dbg !423
  %t1265 = zext i32 %t1264 to i64, !dbg !423
  %t1266 = icmp uge i64 %t1265, %t15, !dbg !423
  br i1 %t1266, label %lua.raise.349, label %lua.ok.350, !prof !7, !dbg !423
lua.raise.349:
  %t1267 = getelementptr inbounds ptr, ptr %t1, i64 11, !dbg !423
  %rt.raise.1268 = load ptr, ptr %t1267, !invariant.load !8, !dbg !423
  call void %rt.raise.1268(ptr %L, i64 3) nomerge, !dbg !423
  unreachable, !dbg !423
lua.ok.350:
  %t1269 = getelementptr inbounds i8, ptr %t14, i64 %t1265, !dbg !423
  %t1270 = load i8, ptr %t1269, !dbg !423
  %t1271 = zext i8 %t1270 to i32, !dbg !423
  store i32 %t1271, ptr %slot502, !dbg !423
  %t1272 = load i32, ptr %slot502, !dbg !424
  %t1273 = icmp ult i32 %t1272, 128, !dbg !424
  br i1 %t1273, label %if.then.352, label %if.else.353, !dbg !424
if.then.352:
  store i1 false, ptr %slot483, !dbg !425
  br label %if.end.351, !dbg !425
if.else.353:
  %t1274 = load i32, ptr %slot502, !dbg !425
  %t1275 = icmp uge i32 %t1274, 192, !dbg !425
  br i1 %t1275, label %if.then.354, label %if.else.355, !dbg !425
if.then.354:
  %t1276 = load i32, ptr %slot502, !dbg !426
  %t1277 = icmp ult i32 %t1276, 194, !dbg !426
  br i1 %t1277, label %or.end.358, label %or.rhs.357, !dbg !426
or.rhs.357:
  %t1278 = load i32, ptr %slot502, !dbg !426
  %t1279 = icmp ugt i32 %t1278, 244, !dbg !426
  br label %or.end.358, !dbg !426
or.end.358:
  %t1280 = phi i1 [ true, %if.then.354 ], [ %t1279, %or.rhs.357 ], !dbg !426
  br i1 %t1280, label %if.then.359, label %if.else.360, !dbg !426
if.then.359:
  call void @lua_pushvalue(ptr %L, i32 2), !dbg !427
  %t1281 = call i32 @nupp.wrap.u32(double 0x4000000000000000), !dbg !427
  %t1282 = uitofp i32 %t1281 to double, !dbg !427
  call void @lua_pushnumber(ptr %L, double %t1282), !dbg !427
  %t1283 = load i32, ptr %slot33, !dbg !427
  %t1284 = load i32, ptr %slot482, !dbg !427
  %t1285 = sub i32 %t1283, %t1284, !dbg !427
  %t1286 = add i32 %t1285, 1, !dbg !427
  %t1287 = uitofp i32 %t1286 to double, !dbg !427
  call void @lua_pushnumber(ptr %L, double %t1287), !dbg !427
  ret i32 3, !dbg !427
if.else.360:
  br label %if.end.356, !dbg !427
if.end.356:
  %t1288 = call i32 @nupp.wrap.u32(double 0x4008000000000000), !dbg !428
  store i32 %t1288, ptr %slot520, !dbg !428
  %t1289 = load i32, ptr %slot502, !dbg !429
  %t1290 = icmp ule i32 %t1289, 223, !dbg !429
  br i1 %t1290, label %if.then.362, label %if.else.363, !dbg !429
if.then.362:
  %t1291 = call i32 @nupp.wrap.u32(double 0x3FF0000000000000), !dbg !430
  store i32 %t1291, ptr %slot520, !dbg !430
  br label %if.end.361, !dbg !430
if.else.363:
  %t1292 = load i32, ptr %slot502, !dbg !430
  %t1293 = icmp ule i32 %t1292, 239, !dbg !430
  br i1 %t1293, label %if.then.364, label %if.else.365, !dbg !430
if.then.364:
  %t1294 = call i32 @nupp.wrap.u32(double 0x4000000000000000), !dbg !431
  store i32 %t1294, ptr %slot520, !dbg !431
  br label %if.end.361, !dbg !431
if.else.365:
  br label %if.end.361, !dbg !431
if.end.361:
  %t1295 = load i32, ptr %slot520, !dbg !432
  %t1296 = load i32, ptr %slot482, !dbg !432
  %t1297 = icmp uge i32 %t1295, %t1296, !dbg !432
  br i1 %t1297, label %if.then.367, label %if.else.368, !dbg !432
if.then.367:
  %t1298 = load i32, ptr %slot520, !dbg !433
  %t1299 = load i32, ptr %slot482, !dbg !433
  %t1300 = sub i32 %t1298, %t1299, !dbg !433
  %t1301 = add i32 %t1300, 1, !dbg !433
  store i32 %t1301, ptr %slot43, !dbg !433
  store i1 true, ptr %slot46, !dbg !434
  %t1302 = load i32, ptr %slot33, !dbg !435
  %t1303 = sub i32 %t1302, 1, !dbg !435
  store i32 %t1303, ptr %slot48, !dbg !435
  %t1304 = load i32, ptr %slot482, !dbg !436
  %t1305 = icmp eq i32 %t1304, 1, !dbg !436
  br i1 %t1305, label %if.then.370, label %if.else.371, !dbg !436
if.then.370:
  %t1306 = load i32, ptr %slot502, !dbg !437
  %t1307 = icmp eq i32 %t1306, 224, !dbg !437
  br i1 %t1307, label %if.then.373, label %if.else.374, !dbg !437
if.then.373:
  %t1308 = call i32 @nupp.wrap.u32(double 0x3FF0000000000000), !dbg !438
  store i32 %t1308, ptr %slot45, !dbg !438
  br label %if.end.372, !dbg !438
if.else.374:
  %t1309 = load i32, ptr %slot502, !dbg !438
  %t1310 = icmp eq i32 %t1309, 237, !dbg !438
  br i1 %t1310, label %if.then.375, label %if.else.376, !dbg !438
if.then.375:
  %t1311 = call i32 @nupp.wrap.u32(double 0x4000000000000000), !dbg !439
  store i32 %t1311, ptr %slot45, !dbg !439
  br label %if.end.372, !dbg !439
if.else.376:
  %t1312 = load i32, ptr %slot502, !dbg !439
  %t1313 = icmp eq i32 %t1312, 240, !dbg !439
  br i1 %t1313, label %if.then.377, label %if.else.378, !dbg !439
if.then.377:
  %t1314 = call i32 @nupp.wrap.u32(double 0x4008000000000000), !dbg !440
  store i32 %t1314, ptr %slot45, !dbg !440
  br label %if.end.372, !dbg !440
if.else.378:
  %t1315 = load i32, ptr %slot502, !dbg !440
  %t1316 = icmp eq i32 %t1315, 244, !dbg !440
  br i1 %t1316, label %if.then.379, label %if.else.380, !dbg !440
if.then.379:
  %t1317 = call i32 @nupp.wrap.u32(double 0x4010000000000000), !dbg !441
  store i32 %t1317, ptr %slot45, !dbg !441
  br label %if.end.372, !dbg !441
if.else.380:
  br label %if.end.372, !dbg !441
if.end.372:
  br label %if.end.369, !dbg !441
if.else.371:
  br label %if.end.369, !dbg !441
if.end.369:
  br label %if.end.366, !dbg !441
if.else.368:
  br label %if.end.366, !dbg !441
if.end.366:
  store i1 false, ptr %slot483, !dbg !442
  br label %if.end.351, !dbg !442
if.else.355:
  %t1318 = load i32, ptr %slot482, !dbg !443
  %t1319 = add i32 %t1318, 1, !dbg !443
  store i32 %t1319, ptr %slot482, !dbg !443
  br label %if.end.351, !dbg !443
if.end.351:
  br label %while.head.342, !dbg !443
while.end.344:
  br label %if.end.337, !dbg !443
if.else.341:
  %t1320 = load i32, ptr %slot70, !dbg !443
  %t1321 = icmp eq i32 %t1320, 0, !dbg !443
  br i1 %t1321, label %if.then.381, label %if.else.382, !dbg !443
if.then.381:
  %t1322 = load i32, ptr %slot33, !dbg !444
  %t1323 = load i32, ptr %slot20, !dbg !444
  %t1324 = icmp ult i32 %t1322, %t1323, !dbg !444
  br i1 %t1324, label %if.then.384, label %if.else.385, !dbg !444
if.then.384:
  %t1325 = load i32, ptr %slot33, !dbg !445
  %t1326 = zext i32 %t1325 to i64, !dbg !445
  %t1327 = getelementptr inbounds i8, ptr %t14, i64 %t1326, !dbg !445
  %t1328 = load i8, ptr %t1327, !dbg !445
  %t1329 = zext i8 %t1328 to i32, !dbg !445
  store i32 %t1329, ptr %slot562, !dbg !445
  %t1330 = load i32, ptr %slot562, !dbg !446
  %t1331 = icmp eq i32 %t1330, 34, !dbg !446
  br i1 %t1331, label %or.end.388, label %or.rhs.387, !dbg !446
or.rhs.387:
  %t1332 = load i32, ptr %slot562, !dbg !446
  %t1333 = icmp eq i32 %t1332, 92, !dbg !446
  br label %or.end.388, !dbg !446
or.end.388:
  %t1334 = phi i1 [ true, %if.then.384 ], [ %t1333, %or.rhs.387 ], !dbg !446
  br i1 %t1334, label %or.end.390, label %or.rhs.389, !dbg !446
or.rhs.389:
  %t1335 = load i32, ptr %slot562, !dbg !446
  %t1336 = icmp ult i32 %t1335, 32, !dbg !446
  br label %or.end.390, !dbg !446
or.end.390:
  %t1337 = phi i1 [ true, %or.end.388 ], [ %t1336, %or.rhs.389 ], !dbg !446
  br i1 %t1337, label %or.end.392, label %or.rhs.391, !dbg !446
or.rhs.391:
  %t1338 = load i32, ptr %slot562, !dbg !446
  %t1339 = icmp eq i32 %t1338, 123, !dbg !446
  br label %or.end.392, !dbg !446
or.end.392:
  %t1340 = phi i1 [ true, %or.end.390 ], [ %t1339, %or.rhs.391 ], !dbg !446
  br i1 %t1340, label %or.end.394, label %or.rhs.393, !dbg !446
or.rhs.393:
  %t1341 = load i32, ptr %slot562, !dbg !446
  %t1342 = icmp eq i32 %t1341, 125, !dbg !446
  br label %or.end.394, !dbg !446
or.end.394:
  %t1343 = phi i1 [ true, %or.end.392 ], [ %t1342, %or.rhs.393 ], !dbg !446
  br i1 %t1343, label %or.end.396, label %or.rhs.395, !dbg !446
or.rhs.395:
  %t1344 = load i32, ptr %slot562, !dbg !446
  %t1345 = icmp eq i32 %t1344, 91, !dbg !446
  br label %or.end.396, !dbg !446
or.end.396:
  %t1346 = phi i1 [ true, %or.end.394 ], [ %t1345, %or.rhs.395 ], !dbg !446
  br i1 %t1346, label %or.end.398, label %or.rhs.397, !dbg !446
or.rhs.397:
  %t1347 = load i32, ptr %slot562, !dbg !446
  %t1348 = icmp eq i32 %t1347, 93, !dbg !446
  br label %or.end.398, !dbg !446
or.end.398:
  %t1349 = phi i1 [ true, %or.end.396 ], [ %t1348, %or.rhs.397 ], !dbg !446
  br i1 %t1349, label %or.end.400, label %or.rhs.399, !dbg !446
or.rhs.399:
  %t1350 = load i32, ptr %slot562, !dbg !446
  %t1351 = icmp eq i32 %t1350, 58, !dbg !446
  br label %or.end.400, !dbg !446
or.end.400:
  %t1352 = phi i1 [ true, %or.end.398 ], [ %t1351, %or.rhs.399 ], !dbg !446
  br i1 %t1352, label %or.end.402, label %or.rhs.401, !dbg !446
or.rhs.401:
  %t1353 = load i32, ptr %slot562, !dbg !446
  %t1354 = icmp eq i32 %t1353, 44, !dbg !446
  br label %or.end.402, !dbg !446
or.end.402:
  %t1355 = phi i1 [ true, %or.end.400 ], [ %t1354, %or.rhs.401 ], !dbg !446
  br i1 %t1355, label %or.end.404, label %or.rhs.403, !dbg !446
or.rhs.403:
  %t1356 = load i32, ptr %slot562, !dbg !446
  %t1357 = icmp uge i32 %t1356, 128, !dbg !446
  br label %or.end.404, !dbg !446
or.end.404:
  %t1358 = phi i1 [ true, %or.end.402 ], [ %t1357, %or.rhs.403 ], !dbg !446
  br i1 %t1358, label %if.then.405, label %if.else.406, !dbg !446
if.then.405:
  %t1359 = load i64, ptr %slot55, !dbg !447
  store i64 %t1359, ptr %slot68, !dbg !447
  br label %if.end.386, !dbg !447
if.else.406:
  br label %if.end.386, !dbg !447
if.end.386:
  br label %if.end.383, !dbg !447
if.else.385:
  br label %if.end.383, !dbg !447
if.end.383:
  %t1360 = call i32 @nupp.wrap.u32(double 0x3FF0000000000000), !dbg !448
  store i32 %t1360, ptr %slot70, !dbg !448
  br label %if.end.337, !dbg !448
if.else.382:
  br label %if.end.337, !dbg !448
if.end.337:
  br label %while.head.407, !dbg !449
while.head.407:
  %t1361 = load i64, ptr %slot68, !dbg !449
  %t1362 = call i64 @llvm.fptosi.sat.i64.f64(double 0x0000000000000000), !dbg !449
  %t1363 = call i64 @llvm.fptoui.sat.i64.f64(double 0x0000000000000000), !dbg !449
  %t1364 = fcmp olt double 0x0000000000000000, 0.0, !dbg !449
  %t1365 = select i1 %t1364, i64 %t1362, i64 %t1363, !dbg !449
  %t1366 = icmp ne i64 %t1361, %t1365, !dbg !449
  br i1 %t1366, label %while.body.408, label %while.end.409, !dbg !449
while.body.408:
  %t1367 = load i64, ptr %slot68, !dbg !450
  %t1368 = call i64 @llvm.cttz.i64(i64 %t1367, i1 false), !dbg !450
  %t1369 = trunc i64 %t1368 to i32, !dbg !450
  store i32 %t1369, ptr %slot603, !dbg !450
  %t1370 = load i64, ptr %slot68, !dbg !451
  %t1371 = load i64, ptr %slot68, !dbg !451
  %t1372 = call i64 @llvm.fptosi.sat.i64.f64(double 0x3FF0000000000000), !dbg !451
  %t1373 = call i64 @llvm.fptoui.sat.i64.f64(double 0x3FF0000000000000), !dbg !451
  %t1374 = fcmp olt double 0x3FF0000000000000, 0.0, !dbg !451
  %t1375 = select i1 %t1374, i64 %t1372, i64 %t1373, !dbg !451
  %t1376 = sub i64 %t1371, %t1375, !dbg !451
  %t1377 = and i64 %t1370, %t1376, !dbg !451
  store i64 %t1377, ptr %slot68, !dbg !451
  %t1378 = load i32, ptr %slot33, !dbg !452
  %t1379 = load i32, ptr %slot603, !dbg !452
  %t1380 = add i32 %t1378, %t1379, !dbg !452
  store i32 %t1380, ptr %slot615, !dbg !452
  %t1381 = load i32, ptr %slot615, !dbg !453
  %t1382 = load i32, ptr %slot20, !dbg !453
  %t1383 = icmp ult i32 %t1381, %t1382, !dbg !453
  br i1 %t1383, label %if.then.411, label %if.else.412, !dbg !453
if.then.411:
  %t1384 = load i32, ptr %slot615, !dbg !454
  %t1385 = zext i32 %t1384 to i64, !dbg !454
  %t1386 = getelementptr inbounds i8, ptr %t14, i64 %t1385, !dbg !454
  %t1387 = load i8, ptr %t1386, !dbg !454
  %t1388 = zext i8 %t1387 to i32, !dbg !454
  store i32 %t1388, ptr %slot624, !dbg !454
  %t1389 = load i32, ptr %slot43, !dbg !455
  %t1390 = icmp ne i32 %t1389, 0, !dbg !455
  br i1 %t1390, label %and.rhs.414, label %and.end.415, !dbg !455
and.rhs.414:
  %t1391 = load i1, ptr %slot46, !dbg !455
  %t1392 = xor i1 %t1391, true, !dbg !455
  br i1 %t1392, label %or.end.417, label %or.rhs.416, !dbg !455
or.rhs.416:
  %t1393 = load i32, ptr %slot615, !dbg !455
  %t1394 = load i32, ptr %slot48, !dbg !455
  %t1395 = add i32 %t1394, 1, !dbg !455
  %t1396 = icmp ne i32 %t1393, %t1395, !dbg !455
  br label %or.end.417, !dbg !455
or.end.417:
  %t1397 = phi i1 [ true, %and.rhs.414 ], [ %t1396, %or.rhs.416 ], !dbg !455
  br label %and.end.415, !dbg !455
and.end.415:
  %t1398 = phi i1 [ false, %if.then.411 ], [ %t1397, %or.end.417 ], !dbg !455
  br i1 %t1398, label %if.then.418, label %if.else.419, !dbg !455
if.then.418:
  call void @lua_pushvalue(ptr %L, i32 2), !dbg !456
  %t1399 = call i32 @nupp.wrap.u32(double 0x4000000000000000), !dbg !456
  %t1400 = uitofp i32 %t1399 to double, !dbg !456
  call void @lua_pushnumber(ptr %L, double %t1400), !dbg !456
  %t1401 = load i32, ptr %slot48, !dbg !456
  %t1402 = add i32 %t1401, 2, !dbg !456
  %t1403 = uitofp i32 %t1402 to double, !dbg !456
  call void @lua_pushnumber(ptr %L, double %t1403), !dbg !456
  ret i32 3, !dbg !456
if.else.419:
  br label %if.end.413, !dbg !456
if.end.413:
  %t1404 = load i32, ptr %slot624, !dbg !457
  %t1405 = icmp uge i32 %t1404, 128, !dbg !457
  br i1 %t1405, label %if.then.421, label %if.else.422, !dbg !457
if.then.421:
  %t1406 = load i32, ptr %slot624, !dbg !458
  %t1407 = icmp ule i32 %t1406, 191, !dbg !458
  store i1 %t1407, ptr %slot644, !dbg !458
  %t1408 = load i32, ptr %slot43, !dbg !459
  %t1409 = icmp ne i32 %t1408, 0, !dbg !459
  br i1 %t1409, label %if.then.424, label %if.else.425, !dbg !459
if.then.424:
  %t1410 = load i1, ptr %slot644, !dbg !460
  %t1411 = xor i1 %t1410, true, !dbg !460
  br i1 %t1411, label %if.then.427, label %if.else.428, !dbg !460
if.then.427:
  call void @lua_pushvalue(ptr %L, i32 2), !dbg !461
  %t1412 = call i32 @nupp.wrap.u32(double 0x4000000000000000), !dbg !461
  %t1413 = uitofp i32 %t1412 to double, !dbg !461
  call void @lua_pushnumber(ptr %L, double %t1413), !dbg !461
  %t1414 = load i32, ptr %slot615, !dbg !461
  %t1415 = add i32 %t1414, 1, !dbg !461
  %t1416 = uitofp i32 %t1415 to double, !dbg !461
  call void @lua_pushnumber(ptr %L, double %t1416), !dbg !461
  ret i32 3, !dbg !461
if.else.428:
  br label %if.end.426, !dbg !461
if.end.426:
  %t1417 = load i32, ptr %slot45, !dbg !462
  %t1418 = icmp eq i32 %t1417, 1, !dbg !462
  br i1 %t1418, label %and.rhs.429, label %and.end.430, !dbg !462
and.rhs.429:
  %t1419 = load i32, ptr %slot624, !dbg !462
  %t1420 = icmp ult i32 %t1419, 160, !dbg !462
  br label %and.end.430, !dbg !462
and.end.430:
  %t1421 = phi i1 [ false, %if.end.426 ], [ %t1420, %and.rhs.429 ], !dbg !462
  br i1 %t1421, label %or.end.432, label %or.rhs.431, !dbg !462
or.rhs.431:
  %t1422 = load i32, ptr %slot45, !dbg !462
  %t1423 = icmp eq i32 %t1422, 2, !dbg !462
  br i1 %t1423, label %and.rhs.433, label %and.end.434, !dbg !462
and.rhs.433:
  %t1424 = load i32, ptr %slot624, !dbg !462
  %t1425 = icmp ugt i32 %t1424, 159, !dbg !462
  br label %and.end.434, !dbg !462
and.end.434:
  %t1426 = phi i1 [ false, %or.rhs.431 ], [ %t1425, %and.rhs.433 ], !dbg !462
  br label %or.end.432, !dbg !462
or.end.432:
  %t1427 = phi i1 [ true, %and.end.430 ], [ %t1426, %and.end.434 ], !dbg !462
  br i1 %t1427, label %or.end.436, label %or.rhs.435, !dbg !462
or.rhs.435:
  %t1428 = load i32, ptr %slot45, !dbg !462
  %t1429 = icmp eq i32 %t1428, 3, !dbg !462
  br i1 %t1429, label %and.rhs.437, label %and.end.438, !dbg !462
and.rhs.437:
  %t1430 = load i32, ptr %slot624, !dbg !462
  %t1431 = icmp ult i32 %t1430, 144, !dbg !462
  br label %and.end.438, !dbg !462
and.end.438:
  %t1432 = phi i1 [ false, %or.rhs.435 ], [ %t1431, %and.rhs.437 ], !dbg !462
  br label %or.end.436, !dbg !462
or.end.436:
  %t1433 = phi i1 [ true, %or.end.432 ], [ %t1432, %and.end.438 ], !dbg !462
  br i1 %t1433, label %or.end.440, label %or.rhs.439, !dbg !462
or.rhs.439:
  %t1434 = load i32, ptr %slot45, !dbg !462
  %t1435 = icmp eq i32 %t1434, 4, !dbg !462
  br i1 %t1435, label %and.rhs.441, label %and.end.442, !dbg !462
and.rhs.441:
  %t1436 = load i32, ptr %slot624, !dbg !462
  %t1437 = icmp ugt i32 %t1436, 143, !dbg !462
  br label %and.end.442, !dbg !462
and.end.442:
  %t1438 = phi i1 [ false, %or.rhs.439 ], [ %t1437, %and.rhs.441 ], !dbg !462
  br label %or.end.440, !dbg !462
or.end.440:
  %t1439 = phi i1 [ true, %or.end.436 ], [ %t1438, %and.end.442 ], !dbg !462
  store i1 %t1439, ptr %slot677, !dbg !462
  %t1440 = load i1, ptr %slot677, !dbg !463
  br i1 %t1440, label %if.then.444, label %if.else.445, !dbg !463
if.then.444:
  call void @lua_pushvalue(ptr %L, i32 2), !dbg !464
  %t1441 = call i32 @nupp.wrap.u32(double 0x4000000000000000), !dbg !464
  %t1442 = uitofp i32 %t1441 to double, !dbg !464
  call void @lua_pushnumber(ptr %L, double %t1442), !dbg !464
  %t1443 = load i32, ptr %slot615, !dbg !464
  %t1444 = add i32 %t1443, 1, !dbg !464
  %t1445 = uitofp i32 %t1444 to double, !dbg !464
  call void @lua_pushnumber(ptr %L, double %t1445), !dbg !464
  ret i32 3, !dbg !464
if.else.445:
  br label %if.end.443, !dbg !464
if.end.443:
  %t1446 = load i32, ptr %slot43, !dbg !465
  %t1447 = sub i32 %t1446, 1, !dbg !465
  store i32 %t1447, ptr %slot43, !dbg !465
  %t1448 = call i32 @nupp.wrap.u32(double 0x0000000000000000), !dbg !466
  store i32 %t1448, ptr %slot45, !dbg !466
  br label %if.end.423, !dbg !466
if.else.425:
  %t1449 = load i1, ptr %slot644, !dbg !466
  br i1 %t1449, label %or.end.447, label %or.rhs.446, !dbg !466
or.rhs.446:
  %t1450 = load i32, ptr %slot624, !dbg !466
  %t1451 = icmp ult i32 %t1450, 194, !dbg !466
  br label %or.end.447, !dbg !466
or.end.447:
  %t1452 = phi i1 [ true, %if.else.425 ], [ %t1451, %or.rhs.446 ], !dbg !466
  br i1 %t1452, label %or.end.449, label %or.rhs.448, !dbg !466
or.rhs.448:
  %t1453 = load i32, ptr %slot624, !dbg !466
  %t1454 = icmp ugt i32 %t1453, 244, !dbg !466
  br label %or.end.449, !dbg !466
or.end.449:
  %t1455 = phi i1 [ true, %or.end.447 ], [ %t1454, %or.rhs.448 ], !dbg !466
  br i1 %t1455, label %if.then.450, label %if.else.451, !dbg !466
if.then.450:
  call void @lua_pushvalue(ptr %L, i32 2), !dbg !467
  %t1456 = call i32 @nupp.wrap.u32(double 0x4000000000000000), !dbg !467
  %t1457 = uitofp i32 %t1456 to double, !dbg !467
  call void @lua_pushnumber(ptr %L, double %t1457), !dbg !467
  %t1458 = load i32, ptr %slot615, !dbg !467
  %t1459 = add i32 %t1458, 1, !dbg !467
  %t1460 = uitofp i32 %t1459 to double, !dbg !467
  call void @lua_pushnumber(ptr %L, double %t1460), !dbg !467
  ret i32 3, !dbg !467
if.else.451:
  %t1461 = load i32, ptr %slot624, !dbg !467
  %t1462 = icmp ule i32 %t1461, 223, !dbg !467
  br i1 %t1462, label %if.then.452, label %if.else.453, !dbg !467
if.then.452:
  %t1463 = call i32 @nupp.wrap.u32(double 0x3FF0000000000000), !dbg !468
  store i32 %t1463, ptr %slot43, !dbg !468
  br label %if.end.423, !dbg !468
if.else.453:
  %t1464 = load i32, ptr %slot624, !dbg !468
  %t1465 = icmp ule i32 %t1464, 239, !dbg !468
  br i1 %t1465, label %if.then.454, label %if.else.455, !dbg !468
if.then.454:
  %t1466 = call i32 @nupp.wrap.u32(double 0x4000000000000000), !dbg !469
  store i32 %t1466, ptr %slot43, !dbg !469
  %t1467 = load i32, ptr %slot624, !dbg !470
  %t1468 = icmp eq i32 %t1467, 224, !dbg !470
  br i1 %t1468, label %if.then.457, label %if.else.458, !dbg !470
if.then.457:
  %t1469 = call i32 @nupp.wrap.u32(double 0x3FF0000000000000), !dbg !471
  store i32 %t1469, ptr %slot45, !dbg !471
  br label %if.end.456, !dbg !471
if.else.458:
  %t1470 = load i32, ptr %slot624, !dbg !471
  %t1471 = icmp eq i32 %t1470, 237, !dbg !471
  br i1 %t1471, label %if.then.459, label %if.else.460, !dbg !471
if.then.459:
  %t1472 = call i32 @nupp.wrap.u32(double 0x4000000000000000), !dbg !472
  store i32 %t1472, ptr %slot45, !dbg !472
  br label %if.end.456, !dbg !472
if.else.460:
  br label %if.end.456, !dbg !472
if.end.456:
  br label %if.end.423, !dbg !472
if.else.455:
  %t1473 = call i32 @nupp.wrap.u32(double 0x4008000000000000), !dbg !473
  store i32 %t1473, ptr %slot43, !dbg !473
  %t1474 = load i32, ptr %slot624, !dbg !474
  %t1475 = icmp eq i32 %t1474, 240, !dbg !474
  br i1 %t1475, label %if.then.462, label %if.else.463, !dbg !474
if.then.462:
  %t1476 = call i32 @nupp.wrap.u32(double 0x4008000000000000), !dbg !475
  store i32 %t1476, ptr %slot45, !dbg !475
  br label %if.end.461, !dbg !475
if.else.463:
  %t1477 = load i32, ptr %slot624, !dbg !475
  %t1478 = icmp eq i32 %t1477, 244, !dbg !475
  br i1 %t1478, label %if.then.464, label %if.else.465, !dbg !475
if.then.464:
  %t1479 = call i32 @nupp.wrap.u32(double 0x4010000000000000), !dbg !476
  store i32 %t1479, ptr %slot45, !dbg !476
  br label %if.end.461, !dbg !476
if.else.465:
  br label %if.end.461, !dbg !476
if.end.461:
  br label %if.end.423, !dbg !476
if.end.423:
  store i1 true, ptr %slot46, !dbg !477
  %t1480 = load i32, ptr %slot615, !dbg !478
  store i32 %t1480, ptr %slot48, !dbg !478
  store i1 false, ptr %slot39, !dbg !479
  store i1 false, ptr %slot38, !dbg !480
  br label %if.end.420, !dbg !480
if.else.422:
  %t1481 = load i32, ptr %slot43, !dbg !480
  %t1482 = icmp ne i32 %t1481, 0, !dbg !480
  br i1 %t1482, label %if.then.466, label %if.else.467, !dbg !480
if.then.466:
  call void @lua_pushvalue(ptr %L, i32 2), !dbg !481
  %t1483 = call i32 @nupp.wrap.u32(double 0x4000000000000000), !dbg !481
  %t1484 = uitofp i32 %t1483 to double, !dbg !481
  call void @lua_pushnumber(ptr %L, double %t1484), !dbg !481
  %t1485 = load i32, ptr %slot615, !dbg !481
  %t1486 = add i32 %t1485, 1, !dbg !481
  %t1487 = uitofp i32 %t1486 to double, !dbg !481
  call void @lua_pushnumber(ptr %L, double %t1487), !dbg !481
  ret i32 3, !dbg !481
if.else.467:
  %t1488 = load i32, ptr %slot624, !dbg !481
  %t1489 = icmp eq i32 %t1488, 92, !dbg !481
  br i1 %t1489, label %if.then.468, label %if.else.469, !dbg !481
if.then.468:
  %t1490 = load i1, ptr %slot36, !dbg !482
  %t1491 = xor i1 %t1490, true, !dbg !482
  br i1 %t1491, label %if.then.471, label %if.else.472, !dbg !482
if.then.471:
  call void @lua_pushvalue(ptr %L, i32 2), !dbg !483
  %t1492 = call i32 @nupp.wrap.u32(double 0x4010000000000000), !dbg !483
  %t1493 = uitofp i32 %t1492 to double, !dbg !483
  call void @lua_pushnumber(ptr %L, double %t1493), !dbg !483
  %t1494 = load i32, ptr %slot615, !dbg !483
  %t1495 = add i32 %t1494, 1, !dbg !483
  %t1496 = uitofp i32 %t1495 to double, !dbg !483
  call void @lua_pushnumber(ptr %L, double %t1496), !dbg !483
  ret i32 3, !dbg !483
if.else.472:
  br label %if.end.470, !dbg !483
if.end.470:
  %t1497 = load i1, ptr %slot39, !dbg !484
  br i1 %t1497, label %and.rhs.474, label %and.end.475, !dbg !484
and.rhs.474:
  %t1498 = load i32, ptr %slot615, !dbg !484
  %t1499 = load i32, ptr %slot41, !dbg !484
  %t1500 = add i32 %t1499, 1, !dbg !484
  %t1501 = icmp eq i32 %t1498, %t1500, !dbg !484
  br label %and.end.475, !dbg !484
and.end.475:
  %t1502 = phi i1 [ false, %if.end.470 ], [ %t1501, %and.rhs.474 ], !dbg !484
  br i1 %t1502, label %if.then.476, label %if.else.477, !dbg !484
if.then.476:
  %t1503 = load i1, ptr %slot38, !dbg !485
  %t1504 = xor i1 %t1503, true, !dbg !485
  store i1 %t1504, ptr %slot38, !dbg !485
  br label %if.end.473, !dbg !485
if.else.477:
  store i1 true, ptr %slot38, !dbg !486
  br label %if.end.473, !dbg !486
if.end.473:
  store i1 true, ptr %slot39, !dbg !487
  %t1505 = load i32, ptr %slot615, !dbg !488
  store i32 %t1505, ptr %slot41, !dbg !488
  store i1 true, ptr %slot37, !dbg !489
  br label %if.end.420, !dbg !489
if.else.469:
  %t1506 = load i1, ptr %slot39, !dbg !490
  br i1 %t1506, label %and.rhs.478, label %and.end.479, !dbg !490
and.rhs.478:
  %t1507 = load i32, ptr %slot615, !dbg !490
  %t1508 = load i32, ptr %slot41, !dbg !490
  %t1509 = add i32 %t1508, 1, !dbg !490
  %t1510 = icmp eq i32 %t1507, %t1509, !dbg !490
  br label %and.end.479, !dbg !490
and.end.479:
  %t1511 = phi i1 [ false, %if.else.469 ], [ %t1510, %and.rhs.478 ], !dbg !490
  br i1 %t1511, label %and.rhs.480, label %and.end.481, !dbg !490
and.rhs.480:
  %t1512 = load i1, ptr %slot38, !dbg !490
  br label %and.end.481, !dbg !490
and.end.481:
  %t1513 = phi i1 [ false, %and.end.479 ], [ %t1512, %and.rhs.480 ], !dbg !490
  store i1 %t1513, ptr %slot752, !dbg !490
  %t1514 = load i32, ptr %slot624, !dbg !491
  %t1515 = icmp eq i32 %t1514, 34, !dbg !491
  br i1 %t1515, label %and.rhs.483, label %and.end.484, !dbg !491
and.rhs.483:
  %t1516 = load i1, ptr %slot752, !dbg !491
  %t1517 = xor i1 %t1516, true, !dbg !491
  br label %and.end.484, !dbg !491
and.end.484:
  %t1518 = phi i1 [ false, %and.end.481 ], [ %t1517, %and.rhs.483 ], !dbg !491
  br i1 %t1518, label %if.then.485, label %if.else.486, !dbg !491
if.then.485:
  %t1519 = load i1, ptr %slot36, !dbg !492
  br i1 %t1519, label %if.then.488, label %if.else.489, !dbg !492
if.then.488:
  %t1520 = load i32, ptr %slot615, !dbg !493
  store i32 %t1520, ptr %slot760, !dbg !493
  %t1521 = load i1, ptr %slot37, !dbg !494
  br i1 %t1521, label %if.then.491, label %if.else.492, !dbg !494
if.then.491:
  %t1522 = load i32, ptr %slot615, !dbg !495
  %t1523 = or i32 %t1522, 2147483648, !dbg !495
  store i32 %t1523, ptr %slot760, !dbg !495
  br label %if.end.490, !dbg !495
if.else.492:
  br label %if.end.490, !dbg !495
if.end.490:
  %t1524 = load i32, ptr %slot35, !dbg !496
  %t1525 = load i32, ptr %slot760, !dbg !496
  %t1526 = getelementptr inbounds { ptr, i32, i32, i32, i32, [32 x i32] }, ptr %slot27, i32 0, i32 2, !dbg !496
  %t1527 = load i32, ptr %t1526, !dbg !496
  %t1528 = getelementptr inbounds { ptr, i32, i32, i32, i32, [32 x i32] }, ptr %slot27, i32 0, i32 1, !dbg !496
  %t1529 = load i32, ptr %t1528, !dbg !496
  %t1530 = icmp ugt i32 %t1524, %t1527, !dbg !496
  %t1531 = icmp uge i32 %t1524, %t1529, !dbg !496
  %t1532 = or i1 %t1530, %t1531, !dbg !496
  br i1 %t1532, label %lua.raise.493, label %lua.ok.494, !prof !7, !dbg !496
lua.raise.493:
  %t1533 = getelementptr inbounds ptr, ptr %t1, i64 11, !dbg !496
  %rt.raise.1534 = load ptr, ptr %t1533, !invariant.load !8, !dbg !496
  call void %rt.raise.1534(ptr %L, i64 8) nomerge, !dbg !496
  unreachable, !dbg !496
lua.ok.494:
  %t1535 = icmp eq i32 %t1524, %t1527, !dbg !496
  %t1536 = add i32 %t1527, 1, !dbg !496
  %t1537 = select i1 %t1535, i32 %t1536, i32 %t1527, !dbg !496
  store i32 %t1537, ptr %t1526, !dbg !496
  %t1538 = getelementptr inbounds { ptr, i32, i32, i32, i32, [32 x i32] }, ptr %slot27, i32 0, i32 0, !dbg !496
  %t1539 = load ptr, ptr %t1538, !dbg !496
  %t1540 = zext i32 %t1524 to i64, !dbg !496
  %t1541 = getelementptr inbounds i32, ptr %t1539, i64 %t1540, !dbg !496
  store i32 %t1525, ptr %t1541, !dbg !496
  store i1 false, ptr %slot36, !dbg !497
  br label %if.end.487, !dbg !497
if.else.489:
  %t1542 = load i32, ptr %slot35, !dbg !498
  %t1543 = load i32, ptr %slot615, !dbg !498
  %t1544 = getelementptr inbounds { ptr, i32, i32, i32, i32, [32 x i32] }, ptr %slot27, i32 0, i32 2, !dbg !498
  %t1545 = load i32, ptr %t1544, !dbg !498
  %t1546 = getelementptr inbounds { ptr, i32, i32, i32, i32, [32 x i32] }, ptr %slot27, i32 0, i32 1, !dbg !498
  %t1547 = load i32, ptr %t1546, !dbg !498
  %t1548 = icmp ugt i32 %t1542, %t1545, !dbg !498
  %t1549 = icmp uge i32 %t1542, %t1547, !dbg !498
  %t1550 = or i1 %t1548, %t1549, !dbg !498
  br i1 %t1550, label %lua.raise.495, label %lua.ok.496, !prof !7, !dbg !498
lua.raise.495:
  %t1551 = getelementptr inbounds ptr, ptr %t1, i64 11, !dbg !498
  %rt.raise.1552 = load ptr, ptr %t1551, !invariant.load !8, !dbg !498
  call void %rt.raise.1552(ptr %L, i64 8) nomerge, !dbg !498
  unreachable, !dbg !498
lua.ok.496:
  %t1553 = icmp eq i32 %t1542, %t1545, !dbg !498
  %t1554 = add i32 %t1545, 1, !dbg !498
  %t1555 = select i1 %t1553, i32 %t1554, i32 %t1545, !dbg !498
  store i32 %t1555, ptr %t1544, !dbg !498
  %t1556 = getelementptr inbounds { ptr, i32, i32, i32, i32, [32 x i32] }, ptr %slot27, i32 0, i32 0, !dbg !498
  %t1557 = load ptr, ptr %t1556, !dbg !498
  %t1558 = zext i32 %t1542 to i64, !dbg !498
  %t1559 = getelementptr inbounds i32, ptr %t1557, i64 %t1558, !dbg !498
  store i32 %t1543, ptr %t1559, !dbg !498
  store i1 true, ptr %slot36, !dbg !499
  store i1 false, ptr %slot37, !dbg !500
  br label %if.end.487, !dbg !500
if.end.487:
  %t1560 = load i32, ptr %slot35, !dbg !501
  %t1561 = add i32 %t1560, 1, !dbg !501
  store i32 %t1561, ptr %slot35, !dbg !501
  br label %if.end.482, !dbg !501
if.else.486:
  %t1562 = load i32, ptr %slot624, !dbg !501
  %t1563 = icmp ult i32 %t1562, 32, !dbg !501
  br i1 %t1563, label %if.then.497, label %if.else.498, !dbg !501
if.then.497:
  %t1564 = load i32, ptr %slot624, !dbg !502
  %t1565 = icmp eq i32 %t1564, 9, !dbg !502
  br i1 %t1565, label %or.end.500, label %or.rhs.499, !dbg !502
or.rhs.499:
  %t1566 = load i32, ptr %slot624, !dbg !502
  %t1567 = icmp eq i32 %t1566, 10, !dbg !502
  br label %or.end.500, !dbg !502
or.end.500:
  %t1568 = phi i1 [ true, %if.then.497 ], [ %t1567, %or.rhs.499 ], !dbg !502
  br i1 %t1568, label %or.end.502, label %or.rhs.501, !dbg !502
or.rhs.501:
  %t1569 = load i32, ptr %slot624, !dbg !502
  %t1570 = icmp eq i32 %t1569, 13, !dbg !502
  br label %or.end.502, !dbg !502
or.end.502:
  %t1571 = phi i1 [ true, %or.end.500 ], [ %t1570, %or.rhs.501 ], !dbg !502
  store i1 %t1571, ptr %slot812, !dbg !502
  %t1572 = load i1, ptr %slot36, !dbg !503
  br i1 %t1572, label %or.end.505, label %or.rhs.504, !dbg !503
or.rhs.504:
  %t1573 = load i1, ptr %slot812, !dbg !503
  %t1574 = xor i1 %t1573, true, !dbg !503
  br label %or.end.505, !dbg !503
or.end.505:
  %t1575 = phi i1 [ true, %or.end.502 ], [ %t1574, %or.rhs.504 ], !dbg !503
  br i1 %t1575, label %if.then.506, label %if.else.507, !dbg !503
if.then.506:
  call void @lua_pushvalue(ptr %L, i32 2), !dbg !504
  %t1576 = call i32 @nupp.wrap.u32(double 0x4008000000000000), !dbg !504
  %t1577 = uitofp i32 %t1576 to double, !dbg !504
  call void @lua_pushnumber(ptr %L, double %t1577), !dbg !504
  %t1578 = load i32, ptr %slot615, !dbg !504
  %t1579 = add i32 %t1578, 1, !dbg !504
  %t1580 = uitofp i32 %t1579 to double, !dbg !504
  call void @lua_pushnumber(ptr %L, double %t1580), !dbg !504
  ret i32 3, !dbg !504
if.else.507:
  br label %if.end.503, !dbg !504
if.end.503:
  br label %if.end.482, !dbg !504
if.else.498:
  %t1581 = load i1, ptr %slot36, !dbg !504
  %t1582 = xor i1 %t1581, true, !dbg !504
  br i1 %t1582, label %if.then.508, label %if.else.509, !dbg !504
if.then.508:
  %t1583 = load i32, ptr %slot35, !dbg !505
  %t1584 = load i32, ptr %slot615, !dbg !505
  %t1585 = getelementptr inbounds { ptr, i32, i32, i32, i32, [32 x i32] }, ptr %slot27, i32 0, i32 2, !dbg !505
  %t1586 = load i32, ptr %t1585, !dbg !505
  %t1587 = getelementptr inbounds { ptr, i32, i32, i32, i32, [32 x i32] }, ptr %slot27, i32 0, i32 1, !dbg !505
  %t1588 = load i32, ptr %t1587, !dbg !505
  %t1589 = icmp ugt i32 %t1583, %t1586, !dbg !505
  %t1590 = icmp uge i32 %t1583, %t1588, !dbg !505
  %t1591 = or i1 %t1589, %t1590, !dbg !505
  br i1 %t1591, label %lua.raise.510, label %lua.ok.511, !prof !7, !dbg !505
lua.raise.510:
  %t1592 = getelementptr inbounds ptr, ptr %t1, i64 11, !dbg !505
  %rt.raise.1593 = load ptr, ptr %t1592, !invariant.load !8, !dbg !505
  call void %rt.raise.1593(ptr %L, i64 8) nomerge, !dbg !505
  unreachable, !dbg !505
lua.ok.511:
  %t1594 = icmp eq i32 %t1583, %t1586, !dbg !505
  %t1595 = add i32 %t1586, 1, !dbg !505
  %t1596 = select i1 %t1594, i32 %t1595, i32 %t1586, !dbg !505
  store i32 %t1596, ptr %t1585, !dbg !505
  %t1597 = getelementptr inbounds { ptr, i32, i32, i32, i32, [32 x i32] }, ptr %slot27, i32 0, i32 0, !dbg !505
  %t1598 = load ptr, ptr %t1597, !dbg !505
  %t1599 = zext i32 %t1583 to i64, !dbg !505
  %t1600 = getelementptr inbounds i32, ptr %t1598, i64 %t1599, !dbg !505
  store i32 %t1584, ptr %t1600, !dbg !505
  %t1601 = load i32, ptr %slot35, !dbg !506
  %t1602 = add i32 %t1601, 1, !dbg !506
  store i32 %t1602, ptr %slot35, !dbg !506
  br label %if.end.482, !dbg !506
if.else.509:
  br label %if.end.482, !dbg !506
if.end.482:
  store i1 false, ptr %slot39, !dbg !507
  store i1 false, ptr %slot38, !dbg !508
  br label %if.end.420, !dbg !508
if.end.420:
  br label %if.end.410, !dbg !508
if.else.412:
  br label %if.end.410, !dbg !508
if.end.410:
  br label %while.head.407, !dbg !508
while.end.409:
  %t1603 = load i32, ptr %slot33, !dbg !509
  %t1604 = load i32, ptr %slot70, !dbg !509
  %t1605 = add i32 %t1603, %t1604, !dbg !509
  store i32 %t1605, ptr %slot33, !dbg !509
  br label %while.head.263, !dbg !509
while.end.265:
  br label %cursors.done.13, !dbg !509
cursors.done.13:
  %t1606 = load i32, ptr %slot43, !dbg !510
  %t1607 = icmp ne i32 %t1606, 0, !dbg !510
  br i1 %t1607, label %if.then.513, label %if.else.514, !dbg !510
if.then.513:
  call void @lua_pushvalue(ptr %L, i32 2), !dbg !511
  %t1608 = call i32 @nupp.wrap.u32(double 0x4000000000000000), !dbg !511
  %t1609 = uitofp i32 %t1608 to double, !dbg !511
  call void @lua_pushnumber(ptr %L, double %t1609), !dbg !511
  %t1610 = load i32, ptr %slot48, !dbg !511
  %t1611 = add i32 %t1610, 2, !dbg !511
  %t1612 = uitofp i32 %t1611 to double, !dbg !511
  call void @lua_pushnumber(ptr %L, double %t1612), !dbg !511
  ret i32 3, !dbg !511
if.else.514:
  br label %if.end.512, !dbg !511
if.end.512:
  %t1613 = call i32 @nupp.wrap.u32(double 0x4090000000000000), !dbg !512
  store i32 %t1613, ptr %slot1614, !dbg !512
  %t1615 = load i32, ptr %slot20, !dbg !513
  %t1616 = icmp ule i32 %t1615, 32, !dbg !513
  br i1 %t1616, label %if.then.516, label %if.else.517, !dbg !513
if.then.516:
  %t1617 = call i32 @nupp.wrap.u32(double 0x4030000000000000), !dbg !514
  store i32 %t1617, ptr %slot1614, !dbg !514
  br label %if.end.515, !dbg !514
if.else.517:
  br label %if.end.515, !dbg !514
if.end.515:
  %t1619 = load i32, ptr %slot1614, !dbg !515
  %t1620 = zext i32 %t1619 to i64, !dbg !515
  %t1621 = load i32, ptr %slot20, !dbg !515
  %t1622 = zext i32 %t1621 to i64, !dbg !515
  %t1623 = sext i32 2 to i64, !dbg !515
  %t1624 = sext i32 3 to i64, !dbg !515
  %t1625 = sext i32 4 to i64, !dbg !515
  %t1626 = sext i32 5 to i64, !dbg !515
  %t1627 = sext i32 6 to i64, !dbg !515
  %t1628 = sext i32 7 to i64, !dbg !515
  %t1629 = getelementptr inbounds ptr, ptr %t1, i64 47, !dbg !515
  %rt.builder_init.1630 = load ptr, ptr %t1629, !invariant.load !8, !dbg !515
  call void %rt.builder_init.1630(ptr %L, ptr %slot1618, i64 %t1623, i64 %t1624, i64 %t1625, i64 %t1620, i64 %t1622, i64 %t1626, i64 %t1627, i64 %t1628, i64 0), !dbg !515
  %t1631 = call i32 @nupp.wrap.u32(double 0x0000000000000000), !dbg !516
  store i32 %t1631, ptr %slot1632, !dbg !516
  %t1633 = getelementptr inbounds { ptr, i32, i32, i32, i32, [32 x i32] }, ptr %slot27, i32 0, i32 2, !dbg !517
  %t1634 = load i32, ptr %t1633, !dbg !517
  store i32 %t1634, ptr %slot35, !dbg !517
  %t1635 = call i32 @nupp.wrap.u32(double 0x0000000000000000), !dbg !518
  store i32 %t1635, ptr %slot1636, !dbg !518
  store i1 true, ptr %slot1637, !dbg !519
  store i1 false, ptr %slot1638, !dbg !520
  %t1639 = call i32 @nupp.wrap.u32(double 0x0000000000000000), !dbg !521
  store i32 %t1639, ptr %slot1640, !dbg !521
  br label %while.head.518, !dbg !522
while.head.518:
  %t1641 = load i1, ptr %slot1638, !dbg !522
  %t1642 = xor i1 %t1641, true, !dbg !522
  br i1 %t1642, label %while.body.519, label %while.end.520, !dbg !522
while.body.519:
  store i1 true, ptr %slot1643, !dbg !523
  %t1644 = call i32 @nupp.wrap.u32(double 0x0000000000000000), !dbg !524
  store i32 %t1644, ptr %slot1640, !dbg !524
  br label %while.head.521, !dbg !525
while.head.521:
  %t1645 = load i1, ptr %slot1643, !dbg !525
  br i1 %t1645, label %and.rhs.524, label %and.end.525, !dbg !525
and.rhs.524:
  %t1646 = load i32, ptr %slot1632, !dbg !525
  %t1647 = load i32, ptr %slot20, !dbg !525
  %t1648 = icmp ult i32 %t1646, %t1647, !dbg !525
  br label %and.end.525, !dbg !525
and.end.525:
  %t1649 = phi i1 [ false, %while.head.521 ], [ %t1648, %and.rhs.524 ], !dbg !525
  br i1 %t1649, label %while.body.522, label %while.end.523, !dbg !525
while.body.522:
  %t1650 = load i32, ptr %slot1632, !dbg !526
  %t1651 = zext i32 %t1650 to i64, !dbg !526
  %t1652 = getelementptr inbounds i8, ptr %t14, i64 %t1651, !dbg !526
  %t1653 = load i8, ptr %t1652, !dbg !526
  %t1654 = zext i8 %t1653 to i32, !dbg !526
  store i32 %t1654, ptr %slot1640, !dbg !526
  %t1655 = load i32, ptr %slot1640, !dbg !527
  %t1656 = icmp eq i32 %t1655, 32, !dbg !527
  br i1 %t1656, label %or.end.528, label %or.rhs.527, !dbg !527
or.rhs.527:
  %t1657 = load i32, ptr %slot1640, !dbg !527
  %t1658 = icmp eq i32 %t1657, 9, !dbg !527
  br label %or.end.528, !dbg !527
or.end.528:
  %t1659 = phi i1 [ true, %while.body.522 ], [ %t1658, %or.rhs.527 ], !dbg !527
  br i1 %t1659, label %or.end.530, label %or.rhs.529, !dbg !527
or.rhs.529:
  %t1660 = load i32, ptr %slot1640, !dbg !527
  %t1661 = icmp eq i32 %t1660, 10, !dbg !527
  br label %or.end.530, !dbg !527
or.end.530:
  %t1662 = phi i1 [ true, %or.end.528 ], [ %t1661, %or.rhs.529 ], !dbg !527
  br i1 %t1662, label %or.end.532, label %or.rhs.531, !dbg !527
or.rhs.531:
  %t1663 = load i32, ptr %slot1640, !dbg !527
  %t1664 = icmp eq i32 %t1663, 13, !dbg !527
  br label %or.end.532, !dbg !527
or.end.532:
  %t1665 = phi i1 [ true, %or.end.530 ], [ %t1664, %or.rhs.531 ], !dbg !527
  br i1 %t1665, label %if.then.533, label %if.else.534, !dbg !527
if.then.533:
  %t1666 = load i32, ptr %slot1632, !dbg !528
  %t1667 = add i32 %t1666, 1, !dbg !528
  store i32 %t1667, ptr %slot1632, !dbg !528
  br label %if.end.526, !dbg !528
if.else.534:
  store i1 false, ptr %slot1643, !dbg !529
  br label %if.end.526, !dbg !529
if.end.526:
  br label %while.head.521, !dbg !529
while.end.523:
  %t1668 = load i1, ptr %slot1637, !dbg !530
  br i1 %t1668, label %if.then.536, label %if.else.537, !dbg !530
if.then.536:
  %t1669 = load i32, ptr %slot1632, !dbg !531
  %t1670 = load i32, ptr %slot20, !dbg !531
  %t1671 = icmp uge i32 %t1669, %t1670, !dbg !531
  br i1 %t1671, label %if.then.539, label %if.else.540, !dbg !531
if.then.539:
  call void @lua_pushvalue(ptr %L, i32 2), !dbg !532
  %t1672 = call i32 @nupp.wrap.u32(double 0x3FF0000000000000), !dbg !532
  %t1673 = uitofp i32 %t1672 to double, !dbg !532
  call void @lua_pushnumber(ptr %L, double %t1673), !dbg !532
  %t1674 = load i32, ptr %slot1632, !dbg !532
  %t1675 = add i32 %t1674, 1, !dbg !532
  %t1676 = uitofp i32 %t1675 to double, !dbg !532
  call void @lua_pushnumber(ptr %L, double %t1676), !dbg !532
  ret i32 3, !dbg !532
if.else.540:
  br label %if.end.538, !dbg !532
if.end.538:
  %t1677 = call i32 @nupp.wrap.u32(double 0x0000000000000000), !dbg !533
  store i32 %t1677, ptr %slot1678, !dbg !533
  %t1679 = load i32, ptr %slot1632, !dbg !534
  store i32 %t1679, ptr %slot1680, !dbg !534
  %t1681 = call i32 @nupp.wrap.u32(double 0x0000000000000000), !dbg !535
  store i32 %t1681, ptr %slot1682, !dbg !535
  %t1683 = call i32 @nupp.wrap.u32(double 0x0000000000000000), !dbg !536
  store i32 %t1683, ptr %slot1684, !dbg !536
  %t1685 = call i32 @nupp.wrap.u32(double 0x0000000000000000), !dbg !537
  store i32 %t1685, ptr %slot1686, !dbg !537
  %t1687 = load i32, ptr %slot1640, !dbg !538
  store i32 %t1687, ptr %slot1688, !dbg !538
  %t1689 = load i32, ptr %slot1688, !dbg !539
  %t1690 = icmp eq i32 %t1689, 34, !dbg !539
  br i1 %t1690, label %if.then.542, label %if.else.543, !dbg !539
if.then.542:
  %t1691 = call i32 @nupp.wrap.u32(double 0x4010000000000000), !dbg !540
  store i32 %t1691, ptr %slot1678, !dbg !540
  %t1692 = load i32, ptr %slot1636, !dbg !541
  %t1693 = load i32, ptr %slot35, !dbg !541
  %t1694 = icmp ult i32 %t1692, %t1693, !dbg !541
  br i1 %t1694, label %if.then.545, label %if.else.546, !dbg !541
if.then.545:
  %t1695 = load i32, ptr %slot1636, !dbg !542
  %t1696 = getelementptr inbounds { ptr, i32, i32, i32, i32, [32 x i32] }, ptr %slot27, i32 0, i32 0, !dbg !542
  %t1697 = load ptr, ptr %t1696, !dbg !542
  %t1698 = zext i32 %t1695 to i64, !dbg !542
  %t1699 = getelementptr inbounds i32, ptr %t1697, i64 %t1698, !dbg !542
  %t1700 = load i32, ptr %t1699, !dbg !542
  store i32 %t1700, ptr %slot1701, !dbg !542
  %t1702 = load i32, ptr %slot1701, !dbg !543
  %t1703 = load i32, ptr %slot1632, !dbg !543
  %t1704 = icmp ne i32 %t1702, %t1703, !dbg !543
  br i1 %t1704, label %if.then.548, label %if.else.549, !dbg !543
if.then.548:
  call void @lua_pushvalue(ptr %L, i32 2), !dbg !544
  %t1705 = call i32 @nupp.wrap.u32(double 0x4014000000000000), !dbg !544
  %t1706 = uitofp i32 %t1705 to double, !dbg !544
  call void @lua_pushnumber(ptr %L, double %t1706), !dbg !544
  %t1707 = load i32, ptr %slot1632, !dbg !544
  %t1708 = add i32 %t1707, 1, !dbg !544
  %t1709 = uitofp i32 %t1708 to double, !dbg !544
  call void @lua_pushnumber(ptr %L, double %t1709), !dbg !544
  ret i32 3, !dbg !544
if.else.549:
  br label %if.end.547, !dbg !544
if.end.547:
  %t1710 = load i32, ptr %slot1636, !dbg !545
  %t1711 = add i32 %t1710, 1, !dbg !545
  store i32 %t1711, ptr %slot1636, !dbg !545
  br label %if.end.544, !dbg !545
if.else.546:
  call void @lua_pushvalue(ptr %L, i32 2), !dbg !546
  %t1712 = call i32 @nupp.wrap.u32(double 0x4014000000000000), !dbg !546
  %t1713 = uitofp i32 %t1712 to double, !dbg !546
  call void @lua_pushnumber(ptr %L, double %t1713), !dbg !546
  %t1714 = load i32, ptr %slot1632, !dbg !546
  %t1715 = add i32 %t1714, 1, !dbg !546
  %t1716 = uitofp i32 %t1715 to double, !dbg !546
  call void @lua_pushnumber(ptr %L, double %t1716), !dbg !546
  ret i32 3, !dbg !546
if.end.544:
  %t1717 = load i32, ptr %slot1636, !dbg !547
  %t1718 = load i32, ptr %slot35, !dbg !547
  %t1719 = icmp ult i32 %t1717, %t1718, !dbg !547
  br i1 %t1719, label %if.then.551, label %if.else.552, !dbg !547
if.then.551:
  %t1720 = load i32, ptr %slot1636, !dbg !548
  %t1721 = getelementptr inbounds { ptr, i32, i32, i32, i32, [32 x i32] }, ptr %slot27, i32 0, i32 0, !dbg !548
  %t1722 = load ptr, ptr %t1721, !dbg !548
  %t1723 = zext i32 %t1720 to i64, !dbg !548
  %t1724 = getelementptr inbounds i32, ptr %t1722, i64 %t1723, !dbg !548
  %t1725 = load i32, ptr %t1724, !dbg !548
  store i32 %t1725, ptr %slot1726, !dbg !548
  %t1727 = load i32, ptr %slot1726, !dbg !549
  %t1728 = and i32 %t1727, 2147483647, !dbg !549
  store i32 %t1728, ptr %slot1729, !dbg !549
  %t1730 = load i32, ptr %slot1726, !dbg !550
  %t1731 = and i32 %t1730, 2147483648, !dbg !550
  %t1732 = icmp ne i32 %t1731, 0, !dbg !550
  br i1 %t1732, label %if.then.554, label %if.else.555, !dbg !550
if.then.554:
  %t1733 = call i32 @nupp.wrap.u32(double 0x3FF0000000000000), !dbg !551
  store i32 %t1733, ptr %slot1684, !dbg !551
  br label %if.end.553, !dbg !551
if.else.555:
  br label %if.end.553, !dbg !551
if.end.553:
  %t1734 = load i32, ptr %slot1632, !dbg !552
  %t1735 = add i32 %t1734, 1, !dbg !552
  store i32 %t1735, ptr %slot1680, !dbg !552
  %t1736 = load i32, ptr %slot1729, !dbg !553
  %t1737 = load i32, ptr %slot1680, !dbg !553
  %t1738 = sub i32 %t1736, %t1737, !dbg !553
  store i32 %t1738, ptr %slot1682, !dbg !553
  %t1739 = load i32, ptr %slot1729, !dbg !554
  %t1740 = add i32 %t1739, 1, !dbg !554
  store i32 %t1740, ptr %slot1632, !dbg !554
  %t1741 = load i32, ptr %slot1636, !dbg !555
  %t1742 = add i32 %t1741, 1, !dbg !555
  store i32 %t1742, ptr %slot1636, !dbg !555
  br label %if.end.550, !dbg !555
if.else.552:
  call void @lua_pushvalue(ptr %L, i32 2), !dbg !556
  %t1743 = call i32 @nupp.wrap.u32(double 0x3FF0000000000000), !dbg !556
  %t1744 = uitofp i32 %t1743 to double, !dbg !556
  call void @lua_pushnumber(ptr %L, double %t1744), !dbg !556
  %t1745 = load i32, ptr %slot1632, !dbg !556
  %t1746 = add i32 %t1745, 1, !dbg !556
  %t1747 = uitofp i32 %t1746 to double, !dbg !556
  call void @lua_pushnumber(ptr %L, double %t1747), !dbg !556
  ret i32 3, !dbg !556
if.end.550:
  br label %if.end.541, !dbg !556
if.else.543:
  %t1748 = load i32, ptr %slot1688, !dbg !556
  %t1749 = icmp eq i32 %t1748, 91, !dbg !556
  br i1 %t1749, label %or.end.557, label %or.rhs.556, !dbg !556
or.rhs.556:
  %t1750 = load i32, ptr %slot1688, !dbg !556
  %t1751 = icmp eq i32 %t1750, 123, !dbg !556
  br label %or.end.557, !dbg !556
or.end.557:
  %t1752 = phi i1 [ true, %if.else.543 ], [ %t1751, %or.rhs.556 ], !dbg !556
  br i1 %t1752, label %if.then.558, label %if.else.559, !dbg !556
if.then.558:
  %t1753 = getelementptr inbounds { [10 x i32], i32, i32, i32, i32, i32, i32, ptr, [16 x { i32, i32, i32, i32, i32, i32, i32, i32, i64, i32, i32, i32, i32 }] }, ptr %slot1618, i32 0, i32 1, !dbg !557
  %t1754 = load i32, ptr %t1753, !dbg !557
  %t1755 = load i32, ptr %slot1614, !dbg !557
  %t1756 = icmp uge i32 %t1754, %t1755, !dbg !557
  br i1 %t1756, label %if.then.561, label %if.else.562, !dbg !557
if.then.561:
  call void @lua_pushvalue(ptr %L, i32 2), !dbg !558
  %t1757 = call i32 @nupp.wrap.u32(double 0x3FF0000000000000), !dbg !558
  %t1758 = uitofp i32 %t1757 to double, !dbg !558
  call void @lua_pushnumber(ptr %L, double %t1758), !dbg !558
  %t1759 = load i32, ptr %slot1632, !dbg !558
  %t1760 = add i32 %t1759, 1, !dbg !558
  %t1761 = uitofp i32 %t1760 to double, !dbg !558
  call void @lua_pushnumber(ptr %L, double %t1761), !dbg !558
  ret i32 3, !dbg !558
if.else.562:
  br label %if.end.560, !dbg !558
if.end.560:
  %t1762 = load i32, ptr %slot1688, !dbg !559
  %t1763 = icmp eq i32 %t1762, 91, !dbg !559
  br i1 %t1763, label %if.then.564, label %if.else.565, !dbg !559
if.then.564:
  %t1764 = call i32 @nupp.wrap.u32(double 0x4014000000000000), !dbg !560
  store i32 %t1764, ptr %slot1678, !dbg !560
  br label %if.end.563, !dbg !560
if.else.565:
  %t1765 = call i32 @nupp.wrap.u32(double 0x4018000000000000), !dbg !561
  store i32 %t1765, ptr %slot1678, !dbg !561
  br label %if.end.563, !dbg !561
if.end.563:
  %t1766 = load i32, ptr %slot1632, !dbg !562
  %t1767 = add i32 %t1766, 1, !dbg !562
  store i32 %t1767, ptr %slot1632, !dbg !562
  %t1768 = load i32, ptr %slot1636, !dbg !563
  %t1769 = load i32, ptr %slot35, !dbg !563
  %t1770 = icmp ult i32 %t1768, %t1769, !dbg !563
  br i1 %t1770, label %if.then.567, label %if.else.568, !dbg !563
if.then.567:
  %t1771 = load i32, ptr %slot1688, !dbg !564
  %t1772 = icmp eq i32 %t1771, 123, !dbg !564
  br i1 %t1772, label %if.then.570, label %if.else.571, !dbg !564
if.then.570:
  %t1773 = call i32 @nupp.wrap.u32(double 0x4010000000000000), !dbg !565
  store i32 %t1773, ptr %slot1686, !dbg !565
  br label %if.end.569, !dbg !565
if.else.571:
  %t1774 = getelementptr inbounds { [10 x i32], i32, i32, i32, i32, i32, i32, ptr, [16 x { i32, i32, i32, i32, i32, i32, i32, i32, i64, i32, i32, i32, i32 }] }, ptr %slot1618, i32 0, i32 1, !dbg !565
  %t1775 = load i32, ptr %t1774, !dbg !565
  %t1776 = icmp eq i32 %t1775, 0, !dbg !565
  br i1 %t1776, label %if.then.572, label %if.else.573, !dbg !565
if.then.572:
  %t1777 = load i32, ptr %slot20, !dbg !566
  %t1778 = and i32 5, 31, !dbg !566
  %t1779 = lshr i32 %t1777, %t1778, !dbg !566
  store i32 %t1779, ptr %slot1686, !dbg !566
  %t1780 = load i32, ptr %slot1686, !dbg !567
  %t1781 = icmp ugt i32 %t1780, 262144, !dbg !567
  br i1 %t1781, label %if.then.575, label %if.else.576, !dbg !567
if.then.575:
  %t1782 = call i32 @nupp.wrap.u32(double 0x4110000000000000), !dbg !568
  store i32 %t1782, ptr %slot1686, !dbg !568
  br label %if.end.574, !dbg !568
if.else.576:
  br label %if.end.574, !dbg !568
if.end.574:
  br label %if.end.569, !dbg !568
if.else.573:
  %t1783 = call i32 @nupp.wrap.u32(double 0x4010000000000000), !dbg !569
  store i32 %t1783, ptr %slot1686, !dbg !569
  br label %if.end.569, !dbg !569
if.end.569:
  %t1784 = load i32, ptr %slot1636, !dbg !570
  %t1785 = add i32 %t1784, 1, !dbg !570
  store i32 %t1785, ptr %slot1636, !dbg !570
  br label %if.end.566, !dbg !570
if.else.568:
  call void @lua_pushvalue(ptr %L, i32 2), !dbg !571
  %t1786 = call i32 @nupp.wrap.u32(double 0x4014000000000000), !dbg !571
  %t1787 = uitofp i32 %t1786 to double, !dbg !571
  call void @lua_pushnumber(ptr %L, double %t1787), !dbg !571
  %t1788 = load i32, ptr %slot1632, !dbg !571
  %t1789 = uitofp i32 %t1788 to double, !dbg !571
  call void @lua_pushnumber(ptr %L, double %t1789), !dbg !571
  ret i32 3, !dbg !571
if.end.566:
  br label %if.end.541, !dbg !571
if.else.559:
  %t1790 = load i32, ptr %slot1688, !dbg !571
  %t1791 = icmp eq i32 %t1790, 116, !dbg !571
  br i1 %t1791, label %if.then.577, label %if.else.578, !dbg !571
if.then.577:
  %t1792 = call i32 @nupp.wrap.u32(double 0x3FF0000000000000), !dbg !572
  store i32 %t1792, ptr %slot1678, !dbg !572
  %t1793 = call i32 @nupp.wrap.u32(double 0x0000000000000000), !dbg !573
  store i32 %t1793, ptr %slot1794, !dbg !573
  br label %while.head.579, !dbg !574
while.head.579:
  %t1795 = load i32, ptr %slot1794, !dbg !574
  %t1796 = icmp ult i32 %t1795, 4, !dbg !574
  br i1 %t1796, label %while.body.580, label %while.end.581, !dbg !574
while.body.580:
  %t1797 = load i32, ptr %slot1632, !dbg !575
  %t1798 = load i32, ptr %slot1794, !dbg !575
  %t1799 = add i32 %t1797, %t1798, !dbg !575
  store i32 %t1799, ptr %slot1800, !dbg !575
  %t1801 = load i32, ptr %slot1800, !dbg !576
  %t1802 = load i32, ptr %slot20, !dbg !576
  %t1803 = icmp ult i32 %t1801, %t1802, !dbg !576
  br i1 %t1803, label %if.then.583, label %if.else.584, !dbg !576
if.then.583:
  %t1804 = load i32, ptr %slot1800, !dbg !577
  %t1805 = zext i32 %t1804 to i64, !dbg !577
  %t1806 = getelementptr inbounds i8, ptr %t14, i64 %t1805, !dbg !577
  %t1807 = load i8, ptr %t1806, !dbg !577
  %t1808 = zext i8 %t1807 to i32, !dbg !577
  store i32 %t1808, ptr %slot1809, !dbg !577
  %t1810 = load i32, ptr %slot1794, !dbg !578
  store i32 %t1810, ptr %slot1811, !dbg !578
  store i32 0, ptr %slot1812, !dbg !579
  %t1813 = load i32, ptr %slot1811, !dbg !580
  %t1814 = icmp eq i32 %t1813, 0, !dbg !580
  br i1 %t1814, label %if.then.586, label %if.else.587, !dbg !580
if.then.586:
  %t1815 = call i32 @nupp.wrap.u32(double 0x405D000000000000), !dbg !581
  store i32 %t1815, ptr %slot1812, !dbg !581
  br label %if.end.585, !dbg !581
if.else.587:
  %t1816 = load i32, ptr %slot1811, !dbg !581
  %t1817 = icmp eq i32 %t1816, 1, !dbg !581
  br i1 %t1817, label %if.then.588, label %if.else.589, !dbg !581
if.then.588:
  %t1818 = call i32 @nupp.wrap.u32(double 0x405C800000000000), !dbg !582
  store i32 %t1818, ptr %slot1812, !dbg !582
  br label %if.end.585, !dbg !582
if.else.589:
  %t1819 = load i32, ptr %slot1811, !dbg !582
  %t1820 = icmp eq i32 %t1819, 2, !dbg !582
  br i1 %t1820, label %if.then.590, label %if.else.591, !dbg !582
if.then.590:
  %t1821 = call i32 @nupp.wrap.u32(double 0x405D400000000000), !dbg !583
  store i32 %t1821, ptr %slot1812, !dbg !583
  br label %if.end.585, !dbg !583
if.else.591:
  %t1822 = call i32 @nupp.wrap.u32(double 0x4059400000000000), !dbg !584
  store i32 %t1822, ptr %slot1812, !dbg !584
  br label %if.end.585, !dbg !584
if.end.585:
  %t1823 = load i32, ptr %slot1809, !dbg !585
  %t1824 = load i32, ptr %slot1812, !dbg !585
  %t1825 = icmp ne i32 %t1823, %t1824, !dbg !585
  br i1 %t1825, label %if.then.593, label %if.else.594, !dbg !585
if.then.593:
  call void @lua_pushvalue(ptr %L, i32 2), !dbg !586
  %t1826 = call i32 @nupp.wrap.u32(double 0x3FF0000000000000), !dbg !586
  %t1827 = uitofp i32 %t1826 to double, !dbg !586
  call void @lua_pushnumber(ptr %L, double %t1827), !dbg !586
  %t1828 = load i32, ptr %slot1800, !dbg !586
  %t1829 = add i32 %t1828, 1, !dbg !586
  %t1830 = uitofp i32 %t1829 to double, !dbg !586
  call void @lua_pushnumber(ptr %L, double %t1830), !dbg !586
  ret i32 3, !dbg !586
if.else.594:
  br label %if.end.592, !dbg !586
if.end.592:
  br label %if.end.582, !dbg !586
if.else.584:
  call void @lua_pushvalue(ptr %L, i32 2), !dbg !587
  %t1831 = call i32 @nupp.wrap.u32(double 0x3FF0000000000000), !dbg !587
  %t1832 = uitofp i32 %t1831 to double, !dbg !587
  call void @lua_pushnumber(ptr %L, double %t1832), !dbg !587
  %t1833 = load i32, ptr %slot1800, !dbg !587
  %t1834 = add i32 %t1833, 1, !dbg !587
  %t1835 = uitofp i32 %t1834 to double, !dbg !587
  call void @lua_pushnumber(ptr %L, double %t1835), !dbg !587
  ret i32 3, !dbg !587
if.end.582:
  %t1836 = load i32, ptr %slot1794, !dbg !588
  %t1837 = add i32 %t1836, 1, !dbg !588
  store i32 %t1837, ptr %slot1794, !dbg !588
  br label %while.head.579, !dbg !588
while.end.581:
  %t1838 = call i32 @nupp.wrap.u32(double 0x4010000000000000), !dbg !589
  store i32 %t1838, ptr %slot1682, !dbg !589
  %t1839 = load i32, ptr %slot1632, !dbg !590
  %t1840 = add i32 %t1839, 4, !dbg !590
  store i32 %t1840, ptr %slot1632, !dbg !590
  br label %if.end.541, !dbg !590
if.else.578:
  %t1841 = load i32, ptr %slot1688, !dbg !590
  %t1842 = icmp eq i32 %t1841, 102, !dbg !590
  br i1 %t1842, label %if.then.595, label %if.else.596, !dbg !590
if.then.595:
  %t1843 = call i32 @nupp.wrap.u32(double 0x4000000000000000), !dbg !591
  store i32 %t1843, ptr %slot1678, !dbg !591
  %t1844 = call i32 @nupp.wrap.u32(double 0x0000000000000000), !dbg !592
  store i32 %t1844, ptr %slot1845, !dbg !592
  br label %while.head.597, !dbg !593
while.head.597:
  %t1846 = load i32, ptr %slot1845, !dbg !593
  %t1847 = icmp ult i32 %t1846, 5, !dbg !593
  br i1 %t1847, label %while.body.598, label %while.end.599, !dbg !593
while.body.598:
  %t1848 = load i32, ptr %slot1632, !dbg !594
  %t1849 = load i32, ptr %slot1845, !dbg !594
  %t1850 = add i32 %t1848, %t1849, !dbg !594
  store i32 %t1850, ptr %slot1851, !dbg !594
  %t1852 = load i32, ptr %slot1851, !dbg !595
  %t1853 = load i32, ptr %slot20, !dbg !595
  %t1854 = icmp ult i32 %t1852, %t1853, !dbg !595
  br i1 %t1854, label %if.then.601, label %if.else.602, !dbg !595
if.then.601:
  %t1855 = load i32, ptr %slot1851, !dbg !596
  %t1856 = zext i32 %t1855 to i64, !dbg !596
  %t1857 = getelementptr inbounds i8, ptr %t14, i64 %t1856, !dbg !596
  %t1858 = load i8, ptr %t1857, !dbg !596
  %t1859 = zext i8 %t1858 to i32, !dbg !596
  store i32 %t1859, ptr %slot1860, !dbg !596
  %t1861 = load i32, ptr %slot1845, !dbg !597
  store i32 %t1861, ptr %slot1862, !dbg !597
  store i32 0, ptr %slot1863, !dbg !598
  %t1864 = load i32, ptr %slot1862, !dbg !599
  %t1865 = icmp eq i32 %t1864, 0, !dbg !599
  br i1 %t1865, label %if.then.604, label %if.else.605, !dbg !599
if.then.604:
  %t1866 = call i32 @nupp.wrap.u32(double 0x4059800000000000), !dbg !600
  store i32 %t1866, ptr %slot1863, !dbg !600
  br label %if.end.603, !dbg !600
if.else.605:
  %t1867 = load i32, ptr %slot1862, !dbg !600
  %t1868 = icmp eq i32 %t1867, 1, !dbg !600
  br i1 %t1868, label %if.then.606, label %if.else.607, !dbg !600
if.then.606:
  %t1869 = call i32 @nupp.wrap.u32(double 0x4058400000000000), !dbg !601
  store i32 %t1869, ptr %slot1863, !dbg !601
  br label %if.end.603, !dbg !601
if.else.607:
  %t1870 = load i32, ptr %slot1862, !dbg !601
  %t1871 = icmp eq i32 %t1870, 2, !dbg !601
  br i1 %t1871, label %if.then.608, label %if.else.609, !dbg !601
if.then.608:
  %t1872 = call i32 @nupp.wrap.u32(double 0x405B000000000000), !dbg !602
  store i32 %t1872, ptr %slot1863, !dbg !602
  br label %if.end.603, !dbg !602
if.else.609:
  %t1873 = load i32, ptr %slot1862, !dbg !602
  %t1874 = icmp eq i32 %t1873, 3, !dbg !602
  br i1 %t1874, label %if.then.610, label %if.else.611, !dbg !602
if.then.610:
  %t1875 = call i32 @nupp.wrap.u32(double 0x405CC00000000000), !dbg !603
  store i32 %t1875, ptr %slot1863, !dbg !603
  br label %if.end.603, !dbg !603
if.else.611:
  %t1876 = call i32 @nupp.wrap.u32(double 0x4059400000000000), !dbg !604
  store i32 %t1876, ptr %slot1863, !dbg !604
  br label %if.end.603, !dbg !604
if.end.603:
  %t1877 = load i32, ptr %slot1860, !dbg !605
  %t1878 = load i32, ptr %slot1863, !dbg !605
  %t1879 = icmp ne i32 %t1877, %t1878, !dbg !605
  br i1 %t1879, label %if.then.613, label %if.else.614, !dbg !605
if.then.613:
  call void @lua_pushvalue(ptr %L, i32 2), !dbg !606
  %t1880 = call i32 @nupp.wrap.u32(double 0x3FF0000000000000), !dbg !606
  %t1881 = uitofp i32 %t1880 to double, !dbg !606
  call void @lua_pushnumber(ptr %L, double %t1881), !dbg !606
  %t1882 = load i32, ptr %slot1851, !dbg !606
  %t1883 = add i32 %t1882, 1, !dbg !606
  %t1884 = uitofp i32 %t1883 to double, !dbg !606
  call void @lua_pushnumber(ptr %L, double %t1884), !dbg !606
  ret i32 3, !dbg !606
if.else.614:
  br label %if.end.612, !dbg !606
if.end.612:
  br label %if.end.600, !dbg !606
if.else.602:
  call void @lua_pushvalue(ptr %L, i32 2), !dbg !607
  %t1885 = call i32 @nupp.wrap.u32(double 0x3FF0000000000000), !dbg !607
  %t1886 = uitofp i32 %t1885 to double, !dbg !607
  call void @lua_pushnumber(ptr %L, double %t1886), !dbg !607
  %t1887 = load i32, ptr %slot1851, !dbg !607
  %t1888 = add i32 %t1887, 1, !dbg !607
  %t1889 = uitofp i32 %t1888 to double, !dbg !607
  call void @lua_pushnumber(ptr %L, double %t1889), !dbg !607
  ret i32 3, !dbg !607
if.end.600:
  %t1890 = load i32, ptr %slot1845, !dbg !608
  %t1891 = add i32 %t1890, 1, !dbg !608
  store i32 %t1891, ptr %slot1845, !dbg !608
  br label %while.head.597, !dbg !608
while.end.599:
  %t1892 = call i32 @nupp.wrap.u32(double 0x4014000000000000), !dbg !609
  store i32 %t1892, ptr %slot1682, !dbg !609
  %t1893 = load i32, ptr %slot1632, !dbg !610
  %t1894 = add i32 %t1893, 5, !dbg !610
  store i32 %t1894, ptr %slot1632, !dbg !610
  br label %if.end.541, !dbg !610
if.else.596:
  %t1895 = load i32, ptr %slot1688, !dbg !610
  %t1896 = icmp eq i32 %t1895, 110, !dbg !610
  br i1 %t1896, label %if.then.615, label %if.else.616, !dbg !610
if.then.615:
  %t1897 = call i32 @nupp.wrap.u32(double 0x0000000000000000), !dbg !611
  store i32 %t1897, ptr %slot1678, !dbg !611
  %t1898 = call i32 @nupp.wrap.u32(double 0x0000000000000000), !dbg !612
  store i32 %t1898, ptr %slot1899, !dbg !612
  br label %while.head.617, !dbg !613
while.head.617:
  %t1900 = load i32, ptr %slot1899, !dbg !613
  %t1901 = icmp ult i32 %t1900, 4, !dbg !613
  br i1 %t1901, label %while.body.618, label %while.end.619, !dbg !613
while.body.618:
  %t1902 = load i32, ptr %slot1632, !dbg !614
  %t1903 = load i32, ptr %slot1899, !dbg !614
  %t1904 = add i32 %t1902, %t1903, !dbg !614
  store i32 %t1904, ptr %slot1905, !dbg !614
  %t1906 = load i32, ptr %slot1905, !dbg !615
  %t1907 = load i32, ptr %slot20, !dbg !615
  %t1908 = icmp ult i32 %t1906, %t1907, !dbg !615
  br i1 %t1908, label %if.then.621, label %if.else.622, !dbg !615
if.then.621:
  %t1909 = load i32, ptr %slot1905, !dbg !616
  %t1910 = zext i32 %t1909 to i64, !dbg !616
  %t1911 = getelementptr inbounds i8, ptr %t14, i64 %t1910, !dbg !616
  %t1912 = load i8, ptr %t1911, !dbg !616
  %t1913 = zext i8 %t1912 to i32, !dbg !616
  store i32 %t1913, ptr %slot1914, !dbg !616
  %t1915 = load i32, ptr %slot1899, !dbg !617
  store i32 %t1915, ptr %slot1916, !dbg !617
  store i32 0, ptr %slot1917, !dbg !618
  %t1918 = load i32, ptr %slot1916, !dbg !619
  %t1919 = icmp eq i32 %t1918, 0, !dbg !619
  br i1 %t1919, label %if.then.624, label %if.else.625, !dbg !619
if.then.624:
  %t1920 = call i32 @nupp.wrap.u32(double 0x405B800000000000), !dbg !620
  store i32 %t1920, ptr %slot1917, !dbg !620
  br label %if.end.623, !dbg !620
if.else.625:
  %t1921 = load i32, ptr %slot1916, !dbg !620
  %t1922 = icmp eq i32 %t1921, 1, !dbg !620
  br i1 %t1922, label %if.then.626, label %if.else.627, !dbg !620
if.then.626:
  %t1923 = call i32 @nupp.wrap.u32(double 0x405D400000000000), !dbg !621
  store i32 %t1923, ptr %slot1917, !dbg !621
  br label %if.end.623, !dbg !621
if.else.627:
  %t1924 = call i32 @nupp.wrap.u32(double 0x405B000000000000), !dbg !622
  store i32 %t1924, ptr %slot1917, !dbg !622
  br label %if.end.623, !dbg !622
if.end.623:
  %t1925 = load i32, ptr %slot1914, !dbg !623
  %t1926 = load i32, ptr %slot1917, !dbg !623
  %t1927 = icmp ne i32 %t1925, %t1926, !dbg !623
  br i1 %t1927, label %if.then.629, label %if.else.630, !dbg !623
if.then.629:
  call void @lua_pushvalue(ptr %L, i32 2), !dbg !624
  %t1928 = call i32 @nupp.wrap.u32(double 0x3FF0000000000000), !dbg !624
  %t1929 = uitofp i32 %t1928 to double, !dbg !624
  call void @lua_pushnumber(ptr %L, double %t1929), !dbg !624
  %t1930 = load i32, ptr %slot1905, !dbg !624
  %t1931 = add i32 %t1930, 1, !dbg !624
  %t1932 = uitofp i32 %t1931 to double, !dbg !624
  call void @lua_pushnumber(ptr %L, double %t1932), !dbg !624
  ret i32 3, !dbg !624
if.else.630:
  br label %if.end.628, !dbg !624
if.end.628:
  br label %if.end.620, !dbg !624
if.else.622:
  call void @lua_pushvalue(ptr %L, i32 2), !dbg !625
  %t1933 = call i32 @nupp.wrap.u32(double 0x3FF0000000000000), !dbg !625
  %t1934 = uitofp i32 %t1933 to double, !dbg !625
  call void @lua_pushnumber(ptr %L, double %t1934), !dbg !625
  %t1935 = load i32, ptr %slot1905, !dbg !625
  %t1936 = add i32 %t1935, 1, !dbg !625
  %t1937 = uitofp i32 %t1936 to double, !dbg !625
  call void @lua_pushnumber(ptr %L, double %t1937), !dbg !625
  ret i32 3, !dbg !625
if.end.620:
  %t1938 = load i32, ptr %slot1899, !dbg !626
  %t1939 = add i32 %t1938, 1, !dbg !626
  store i32 %t1939, ptr %slot1899, !dbg !626
  br label %while.head.617, !dbg !626
while.end.619:
  %t1940 = call i32 @nupp.wrap.u32(double 0x4010000000000000), !dbg !627
  store i32 %t1940, ptr %slot1682, !dbg !627
  %t1941 = load i32, ptr %slot1632, !dbg !628
  %t1942 = add i32 %t1941, 4, !dbg !628
  store i32 %t1942, ptr %slot1632, !dbg !628
  br label %if.end.541, !dbg !628
if.else.616:
  %t1943 = load i32, ptr %slot1688, !dbg !628
  %t1944 = icmp eq i32 %t1943, 45, !dbg !628
  br i1 %t1944, label %or.end.632, label %or.rhs.631, !dbg !628
or.rhs.631:
  %t1945 = load i32, ptr %slot1688, !dbg !628
  %t1946 = icmp uge i32 %t1945, 48, !dbg !628
  br i1 %t1946, label %and.rhs.633, label %and.end.634, !dbg !628
and.rhs.633:
  %t1947 = load i32, ptr %slot1688, !dbg !628
  %t1948 = icmp ule i32 %t1947, 57, !dbg !628
  br label %and.end.634, !dbg !628
and.end.634:
  %t1949 = phi i1 [ false, %or.rhs.631 ], [ %t1948, %and.rhs.633 ], !dbg !628
  br label %or.end.632, !dbg !628
or.end.632:
  %t1950 = phi i1 [ true, %if.else.616 ], [ %t1949, %and.end.634 ], !dbg !628
  br i1 %t1950, label %if.then.635, label %if.else.636, !dbg !628
if.then.635:
  %t1951 = call i32 @nupp.wrap.u32(double 0x4008000000000000), !dbg !629
  store i32 %t1951, ptr %slot1678, !dbg !629
  %t1952 = load i32, ptr %slot1632, !dbg !630
  %t1953 = zext i32 %t1952 to i64, !dbg !630
  %t1954 = load i32, ptr %slot20, !dbg !630
  %t1955 = zext i32 %t1954 to i64, !dbg !630
  %t1956 = getelementptr inbounds ptr, ptr %t1, i64 64, !dbg !630
  %rt.builder_number_token.1957 = load ptr, ptr %t1956, !invariant.load !8, !dbg !630
  %t1958 = call i64 %rt.builder_number_token.1957(ptr %L, ptr %slot1618, ptr %t14, i64 %t15, i64 %t1953, i64 %t1955, i64 0), !dbg !630
  %t1959 = trunc i64 %t1958 to i32, !dbg !630
  store i32 %t1959, ptr %slot1960, !dbg !630
  %t1961 = load i32, ptr %slot1960, !dbg !631
  %t1962 = icmp ult i32 %t1961, 2147483648, !dbg !631
  br i1 %t1962, label %if.then.638, label %if.else.639, !dbg !631
if.then.638:
  call void @lua_pushvalue(ptr %L, i32 2), !dbg !632
  %t1963 = call i32 @nupp.wrap.u32(double 0x3FF0000000000000), !dbg !632
  %t1964 = uitofp i32 %t1963 to double, !dbg !632
  call void @lua_pushnumber(ptr %L, double %t1964), !dbg !632
  %t1965 = load i32, ptr %slot1960, !dbg !632
  %t1966 = uitofp i32 %t1965 to double, !dbg !632
  call void @lua_pushnumber(ptr %L, double %t1966), !dbg !632
  ret i32 3, !dbg !632
if.else.639:
  br label %if.end.637, !dbg !632
if.end.637:
  %t1967 = load i32, ptr %slot1960, !dbg !633
  %t1968 = sub i32 %t1967, 2147483648, !dbg !633
  store i32 %t1968, ptr %slot1632, !dbg !633
  %t1969 = load i32, ptr %slot1632, !dbg !634
  %t1970 = load i32, ptr %slot1680, !dbg !634
  %t1971 = sub i32 %t1969, %t1970, !dbg !634
  store i32 %t1971, ptr %slot1682, !dbg !634
  br label %if.end.541, !dbg !634
if.else.636:
  call void @lua_pushvalue(ptr %L, i32 2), !dbg !635
  %t1972 = call i32 @nupp.wrap.u32(double 0x3FF0000000000000), !dbg !635
  %t1973 = uitofp i32 %t1972 to double, !dbg !635
  call void @lua_pushnumber(ptr %L, double %t1973), !dbg !635
  %t1974 = load i32, ptr %slot1632, !dbg !635
  %t1975 = add i32 %t1974, 1, !dbg !635
  %t1976 = uitofp i32 %t1975 to double, !dbg !635
  call void @lua_pushnumber(ptr %L, double %t1976), !dbg !635
  ret i32 3, !dbg !635
if.end.541:
  %t1977 = load i32, ptr %slot1678, !dbg !636
  %t1978 = icmp eq i32 %t1977, 0, !dbg !636
  br i1 %t1978, label %if.then.641, label %if.else.642, !dbg !636
if.then.641:
  %t1979 = getelementptr inbounds ptr, ptr %t1, i64 57, !dbg !637
  %rt.builder_null.1980 = load ptr, ptr %t1979, !invariant.load !8, !dbg !637
  call void %rt.builder_null.1980(ptr %L, ptr %slot1618, i64 0), !dbg !637
  br label %if.end.640, !dbg !637
if.else.642:
  %t1981 = load i32, ptr %slot1678, !dbg !637
  %t1982 = icmp eq i32 %t1981, 1, !dbg !637
  br i1 %t1982, label %if.then.643, label %if.else.644, !dbg !637
if.then.643:
  %t1983 = zext i1 true to i64, !dbg !638
  %t1984 = getelementptr inbounds ptr, ptr %t1, i64 56, !dbg !638
  %rt.builder_boolean.1985 = load ptr, ptr %t1984, !invariant.load !8, !dbg !638
  call void %rt.builder_boolean.1985(ptr %L, ptr %slot1618, i64 %t1983, i64 0), !dbg !638
  br label %if.end.640, !dbg !638
if.else.644:
  %t1986 = load i32, ptr %slot1678, !dbg !638
  %t1987 = icmp eq i32 %t1986, 2, !dbg !638
  br i1 %t1987, label %if.then.645, label %if.else.646, !dbg !638
if.then.645:
  %t1988 = zext i1 false to i64, !dbg !639
  %t1989 = getelementptr inbounds ptr, ptr %t1, i64 56, !dbg !639
  %rt.builder_boolean.1990 = load ptr, ptr %t1989, !invariant.load !8, !dbg !639
  call void %rt.builder_boolean.1990(ptr %L, ptr %slot1618, i64 %t1988, i64 0), !dbg !639
  br label %if.end.640, !dbg !639
if.else.646:
  %t1991 = load i32, ptr %slot1678, !dbg !639
  %t1992 = icmp eq i32 %t1991, 4, !dbg !639
  br i1 %t1992, label %if.then.647, label %if.else.648, !dbg !639
if.then.647:
  %t1993 = load i32, ptr %slot1680, !dbg !640
  %t1994 = zext i32 %t1993 to i64, !dbg !640
  %t1995 = load i32, ptr %slot1682, !dbg !640
  %t1996 = zext i32 %t1995 to i64, !dbg !640
  %t1997 = load i32, ptr %slot1684, !dbg !640
  %t1998 = icmp eq i32 %t1997, 1, !dbg !640
  %t1999 = zext i1 %t1998 to i64, !dbg !640
  %t2000 = getelementptr inbounds ptr, ptr %t1, i64 49, !dbg !640
  %rt.builder_string.2001 = load ptr, ptr %t2000, !invariant.load !8, !dbg !640
  call void %rt.builder_string.2001(ptr %L, ptr %slot1618, ptr %t14, i64 %t15, i64 %t1994, i64 %t1996, i64 %t1999, i64 0, i64 0), !dbg !640
  br label %if.end.640, !dbg !640
if.else.648:
  %t2002 = load i32, ptr %slot1678, !dbg !640
  %t2003 = icmp eq i32 %t2002, 5, !dbg !640
  br i1 %t2003, label %if.then.649, label %if.else.650, !dbg !640
if.then.649:
  %t2004 = load i32, ptr %slot1686, !dbg !641
  %t2005 = zext i32 %t2004 to i64, !dbg !641
  %t2006 = getelementptr inbounds ptr, ptr %t1, i64 48, !dbg !641
  %rt.builder_open.2007 = load ptr, ptr %t2006, !invariant.load !8, !dbg !641
  call void %rt.builder_open.2007(ptr %L, ptr %slot1618, i64 5, i64 %t2005, i64 0), !dbg !641
  br label %if.end.640, !dbg !641
if.else.650:
  %t2008 = load i32, ptr %slot1678, !dbg !641
  %t2009 = icmp eq i32 %t2008, 6, !dbg !641
  br i1 %t2009, label %if.then.651, label %if.else.652, !dbg !641
if.then.651:
  %t2010 = load i32, ptr %slot1686, !dbg !642
  %t2011 = zext i32 %t2010 to i64, !dbg !642
  %t2012 = getelementptr inbounds ptr, ptr %t1, i64 48, !dbg !642
  %rt.builder_open.2013 = load ptr, ptr %t2012, !invariant.load !8, !dbg !642
  call void %rt.builder_open.2013(ptr %L, ptr %slot1618, i64 6, i64 %t2011, i64 0), !dbg !642
  br label %if.end.640, !dbg !642
if.else.652:
  br label %if.end.640, !dbg !642
if.end.640:
  store i1 false, ptr %slot1637, !dbg !643
  br label %if.end.535, !dbg !643
if.else.537:
  %t2014 = getelementptr inbounds { [10 x i32], i32, i32, i32, i32, i32, i32, ptr, [16 x { i32, i32, i32, i32, i32, i32, i32, i32, i64, i32, i32, i32, i32 }] }, ptr %slot1618, i32 0, i32 1, !dbg !643
  %t2015 = load i32, ptr %t2014, !dbg !643
  %t2016 = icmp eq i32 %t2015, 0, !dbg !643
  br i1 %t2016, label %if.then.653, label %if.else.654, !dbg !643
if.then.653:
  %t2017 = load i32, ptr %slot1632, !dbg !644
  %t2018 = load i32, ptr %slot20, !dbg !644
  %t2019 = icmp ult i32 %t2017, %t2018, !dbg !644
  br i1 %t2019, label %if.then.656, label %if.else.657, !dbg !644
if.then.656:
  call void @lua_pushvalue(ptr %L, i32 2), !dbg !645
  %t2020 = call i32 @nupp.wrap.u32(double 0x3FF0000000000000), !dbg !645
  %t2021 = uitofp i32 %t2020 to double, !dbg !645
  call void @lua_pushnumber(ptr %L, double %t2021), !dbg !645
  %t2022 = load i32, ptr %slot1632, !dbg !645
  %t2023 = add i32 %t2022, 1, !dbg !645
  %t2024 = uitofp i32 %t2023 to double, !dbg !645
  call void @lua_pushnumber(ptr %L, double %t2024), !dbg !645
  ret i32 3, !dbg !645
if.else.657:
  br label %if.end.655, !dbg !645
if.end.655:
  store i1 true, ptr %slot1638, !dbg !646
  br label %if.end.535, !dbg !646
if.else.654:
  %t2025 = load i32, ptr %slot1632, !dbg !647
  %t2026 = load i32, ptr %slot20, !dbg !647
  %t2027 = icmp uge i32 %t2025, %t2026, !dbg !647
  br i1 %t2027, label %if.then.659, label %if.else.660, !dbg !647
if.then.659:
  call void @lua_pushvalue(ptr %L, i32 2), !dbg !648
  %t2028 = call i32 @nupp.wrap.u32(double 0x3FF0000000000000), !dbg !648
  %t2029 = uitofp i32 %t2028 to double, !dbg !648
  call void @lua_pushnumber(ptr %L, double %t2029), !dbg !648
  %t2030 = load i32, ptr %slot1632, !dbg !648
  %t2031 = add i32 %t2030, 1, !dbg !648
  %t2032 = uitofp i32 %t2031 to double, !dbg !648
  call void @lua_pushnumber(ptr %L, double %t2032), !dbg !648
  ret i32 3, !dbg !648
if.else.660:
  br label %if.end.658, !dbg !648
if.end.658:
  %t2033 = getelementptr inbounds { [10 x i32], i32, i32, i32, i32, i32, i32, ptr, [16 x { i32, i32, i32, i32, i32, i32, i32, i32, i64, i32, i32, i32, i32 }] }, ptr %slot1618, i32 0, i32 1, !dbg !649
  %t2034 = load i32, ptr %t2033, !dbg !649
  %t2035 = icmp eq i32 %t2034, 0, !dbg !649
  store i32 0, ptr %slot2036, !dbg !649
  br i1 %t2035, label %lua.state.662, label %lua.frame.661, !dbg !649
lua.frame.661:
  %t2037 = getelementptr inbounds { [10 x i32], i32, i32, i32, i32, i32, i32, ptr, [16 x { i32, i32, i32, i32, i32, i32, i32, i32, i64, i32, i32, i32, i32 }] }, ptr %slot1618, i32 0, i32 7, !dbg !649
  %t2038 = load ptr, ptr %t2037, !dbg !649
  %t2039 = getelementptr inbounds { [10 x i32], i32, i32, i32, i32, i32, i32, ptr, [16 x { i32, i32, i32, i32, i32, i32, i32, i32, i64, i32, i32, i32, i32 }] }, ptr %slot1618, i32 0, i32 8, !dbg !649
  %t2040 = icmp eq ptr %t2038, null, !dbg !649
  %t2041 = select i1 %t2040, ptr %t2039, ptr %t2038, !dbg !649
  %t2042 = sub i32 %t2034, 1, !dbg !649
  %t2043 = zext i32 %t2042 to i64, !dbg !649
  %t2044 = getelementptr inbounds { i32, i32, i32, i32, i32, i32, i32, i32, i64, i32, i32, i32, i32 }, ptr %t2041, i64 %t2043, !dbg !649
  %t2045 = getelementptr inbounds { i32, i32, i32, i32, i32, i32, i32, i32, i64, i32, i32, i32, i32 }, ptr %t2044, i32 0, i32 2, !dbg !649
  %t2046 = load i32, ptr %t2045, !dbg !649
  %t2047 = getelementptr inbounds { i32, i32, i32, i32, i32, i32, i32, i32, i64, i32, i32, i32, i32 }, ptr %t2044, i32 0, i32 4, !dbg !649
  %t2048 = load i32, ptr %t2047, !dbg !649
  %t2049 = icmp ne i32 %t2048, 0, !dbg !649
  %t2050 = select i1 %t2049, i32 256, i32 0, !dbg !649
  %t2051 = or i32 %t2046, %t2050, !dbg !649
  store i32 %t2051, ptr %slot2036, !dbg !649
  br label %lua.state.662, !dbg !649
lua.state.662:
  %t2052 = load i32, ptr %slot2036, !dbg !649
  store i32 %t2052, ptr %slot2053, !dbg !649
  %t2054 = load i32, ptr %slot1640, !dbg !650
  store i32 %t2054, ptr %slot2055, !dbg !650
  %t2056 = load i32, ptr %slot2053, !dbg !651
  %t2057 = and i32 %t2056, 255, !dbg !651
  store i32 %t2057, ptr %slot2058, !dbg !651
  %t2059 = load i32, ptr %slot2053, !dbg !652
  %t2060 = and i32 %t2059, 256, !dbg !652
  %t2061 = icmp ne i32 %t2060, 0, !dbg !652
  store i1 %t2061, ptr %slot2062, !dbg !652
  %t2063 = load i32, ptr %slot2058, !dbg !653
  %t2064 = icmp eq i32 %t2063, 5, !dbg !653
  br i1 %t2064, label %and.rhs.663, label %and.end.664, !dbg !653
and.rhs.663:
  %t2065 = load i32, ptr %slot2055, !dbg !653
  %t2066 = icmp eq i32 %t2065, 93, !dbg !653
  br label %and.end.664, !dbg !653
and.end.664:
  %t2067 = phi i1 [ false, %lua.state.662 ], [ %t2066, %and.rhs.663 ], !dbg !653
  br i1 %t2067, label %or.end.666, label %or.rhs.665, !dbg !653
or.rhs.665:
  %t2068 = load i32, ptr %slot2058, !dbg !653
  %t2069 = icmp eq i32 %t2068, 6, !dbg !653
  br i1 %t2069, label %and.rhs.667, label %and.end.668, !dbg !653
and.rhs.667:
  %t2070 = load i32, ptr %slot2055, !dbg !653
  %t2071 = icmp eq i32 %t2070, 125, !dbg !653
  br label %and.end.668, !dbg !653
and.end.668:
  %t2072 = phi i1 [ false, %or.rhs.665 ], [ %t2071, %and.rhs.667 ], !dbg !653
  br label %or.end.666, !dbg !653
or.end.666:
  %t2073 = phi i1 [ true, %and.end.664 ], [ %t2072, %and.end.668 ], !dbg !653
  store i1 %t2073, ptr %slot2074, !dbg !653
  %t2075 = load i1, ptr %slot2074, !dbg !654
  br i1 %t2075, label %if.then.670, label %if.else.671, !dbg !654
if.then.670:
  %t2076 = load i32, ptr %slot1636, !dbg !655
  %t2077 = load i32, ptr %slot35, !dbg !655
  %t2078 = icmp uge i32 %t2076, %t2077, !dbg !655
  br i1 %t2078, label %or.end.674, label %or.rhs.673, !dbg !655
or.rhs.673:
  %t2079 = load i32, ptr %slot1636, !dbg !655
  %t2080 = getelementptr inbounds { ptr, i32, i32, i32, i32, [32 x i32] }, ptr %slot27, i32 0, i32 0, !dbg !655
  %t2081 = load ptr, ptr %t2080, !dbg !655
  %t2082 = zext i32 %t2079 to i64, !dbg !655
  %t2083 = getelementptr inbounds i32, ptr %t2081, i64 %t2082, !dbg !655
  %t2084 = load i32, ptr %t2083, !dbg !655
  %t2085 = load i32, ptr %slot1632, !dbg !655
  %t2086 = icmp ne i32 %t2084, %t2085, !dbg !655
  br label %or.end.674, !dbg !655
or.end.674:
  %t2087 = phi i1 [ true, %if.then.670 ], [ %t2086, %or.rhs.673 ], !dbg !655
  br i1 %t2087, label %if.then.675, label %if.else.676, !dbg !655
if.then.675:
  call void @lua_pushvalue(ptr %L, i32 2), !dbg !656
  %t2088 = call i32 @nupp.wrap.u32(double 0x4014000000000000), !dbg !656
  %t2089 = uitofp i32 %t2088 to double, !dbg !656
  call void @lua_pushnumber(ptr %L, double %t2089), !dbg !656
  %t2090 = load i32, ptr %slot1632, !dbg !656
  %t2091 = add i32 %t2090, 1, !dbg !656
  %t2092 = uitofp i32 %t2091 to double, !dbg !656
  call void @lua_pushnumber(ptr %L, double %t2092), !dbg !656
  ret i32 3, !dbg !656
if.else.676:
  br label %if.end.672, !dbg !656
if.end.672:
  %t2093 = load i32, ptr %slot1636, !dbg !657
  %t2094 = add i32 %t2093, 1, !dbg !657
  store i32 %t2094, ptr %slot1636, !dbg !657
  %t2095 = load i32, ptr %slot1632, !dbg !658
  %t2096 = add i32 %t2095, 1, !dbg !658
  store i32 %t2096, ptr %slot1632, !dbg !658
  %t2097 = getelementptr inbounds ptr, ptr %t1, i64 58, !dbg !659
  %rt.builder_close.2098 = load ptr, ptr %t2097, !invariant.load !8, !dbg !659
  call void %rt.builder_close.2098(ptr %L, ptr %slot1618, i64 0), !dbg !659
  br label %if.end.669, !dbg !659
if.else.671:
  %t2099 = load i32, ptr %slot2058, !dbg !659
  %t2100 = icmp eq i32 %t2099, 5, !dbg !659
  br i1 %t2100, label %if.then.677, label %if.else.678, !dbg !659
if.then.677:
  %t2101 = load i1, ptr %slot2062, !dbg !660
  %t2102 = xor i1 %t2101, true, !dbg !660
  br i1 %t2102, label %if.then.680, label %if.else.681, !dbg !660
if.then.680:
  store i1 true, ptr %slot1637, !dbg !661
  br label %if.end.679, !dbg !661
if.else.681:
  %t2103 = load i32, ptr %slot2055, !dbg !661
  %t2104 = icmp eq i32 %t2103, 44, !dbg !661
  br i1 %t2104, label %if.then.682, label %if.else.683, !dbg !661
if.then.682:
  %t2105 = load i32, ptr %slot1632, !dbg !662
  %t2106 = add i32 %t2105, 1, !dbg !662
  store i32 %t2106, ptr %slot1632, !dbg !662
  %t2107 = load i32, ptr %slot1636, !dbg !663
  %t2108 = load i32, ptr %slot35, !dbg !663
  %t2109 = icmp uge i32 %t2107, %t2108, !dbg !663
  br i1 %t2109, label %if.then.685, label %if.else.686, !dbg !663
if.then.685:
  call void @lua_pushvalue(ptr %L, i32 2), !dbg !664
  %t2110 = call i32 @nupp.wrap.u32(double 0x4014000000000000), !dbg !664
  %t2111 = uitofp i32 %t2110 to double, !dbg !664
  call void @lua_pushnumber(ptr %L, double %t2111), !dbg !664
  %t2112 = load i32, ptr %slot1632, !dbg !664
  %t2113 = uitofp i32 %t2112 to double, !dbg !664
  call void @lua_pushnumber(ptr %L, double %t2113), !dbg !664
  ret i32 3, !dbg !664
if.else.686:
  br label %if.end.684, !dbg !664
if.end.684:
  %t2114 = load i32, ptr %slot1636, !dbg !665
  %t2115 = add i32 %t2114, 1, !dbg !665
  store i32 %t2115, ptr %slot1636, !dbg !665
  store i1 true, ptr %slot1637, !dbg !666
  br label %if.end.679, !dbg !666
if.else.683:
  call void @lua_pushvalue(ptr %L, i32 2), !dbg !667
  %t2116 = call i32 @nupp.wrap.u32(double 0x3FF0000000000000), !dbg !667
  %t2117 = uitofp i32 %t2116 to double, !dbg !667
  call void @lua_pushnumber(ptr %L, double %t2117), !dbg !667
  %t2118 = load i32, ptr %slot1632, !dbg !667
  %t2119 = add i32 %t2118, 1, !dbg !667
  %t2120 = uitofp i32 %t2119 to double, !dbg !667
  call void @lua_pushnumber(ptr %L, double %t2120), !dbg !667
  ret i32 3, !dbg !667
if.end.679:
  br label %if.end.669, !dbg !667
if.else.678:
  %t2121 = load i1, ptr %slot2062, !dbg !668
  br i1 %t2121, label %if.then.688, label %if.else.689, !dbg !668
if.then.688:
  %t2122 = load i32, ptr %slot2055, !dbg !669
  %t2123 = icmp ne i32 %t2122, 44, !dbg !669
  br i1 %t2123, label %if.then.691, label %if.else.692, !dbg !669
if.then.691:
  call void @lua_pushvalue(ptr %L, i32 2), !dbg !670
  %t2124 = call i32 @nupp.wrap.u32(double 0x3FF0000000000000), !dbg !670
  %t2125 = uitofp i32 %t2124 to double, !dbg !670
  call void @lua_pushnumber(ptr %L, double %t2125), !dbg !670
  %t2126 = load i32, ptr %slot1632, !dbg !670
  %t2127 = add i32 %t2126, 1, !dbg !670
  %t2128 = uitofp i32 %t2127 to double, !dbg !670
  call void @lua_pushnumber(ptr %L, double %t2128), !dbg !670
  ret i32 3, !dbg !670
if.else.692:
  br label %if.end.690, !dbg !670
if.end.690:
  %t2129 = load i32, ptr %slot1632, !dbg !671
  %t2130 = add i32 %t2129, 1, !dbg !671
  store i32 %t2130, ptr %slot1632, !dbg !671
  %t2131 = load i32, ptr %slot1636, !dbg !672
  %t2132 = load i32, ptr %slot35, !dbg !672
  %t2133 = icmp uge i32 %t2131, %t2132, !dbg !672
  br i1 %t2133, label %if.then.694, label %if.else.695, !dbg !672
if.then.694:
  call void @lua_pushvalue(ptr %L, i32 2), !dbg !673
  %t2134 = call i32 @nupp.wrap.u32(double 0x4014000000000000), !dbg !673
  %t2135 = uitofp i32 %t2134 to double, !dbg !673
  call void @lua_pushnumber(ptr %L, double %t2135), !dbg !673
  %t2136 = load i32, ptr %slot1632, !dbg !673
  %t2137 = uitofp i32 %t2136 to double, !dbg !673
  call void @lua_pushnumber(ptr %L, double %t2137), !dbg !673
  ret i32 3, !dbg !673
if.else.695:
  br label %if.end.693, !dbg !673
if.end.693:
  %t2138 = load i32, ptr %slot1636, !dbg !674
  %t2139 = add i32 %t2138, 1, !dbg !674
  store i32 %t2139, ptr %slot1636, !dbg !674
  store i1 true, ptr %slot2140, !dbg !675
  br label %while.head.696, !dbg !676
while.head.696:
  %t2141 = load i1, ptr %slot2140, !dbg !676
  br i1 %t2141, label %and.rhs.699, label %and.end.700, !dbg !676
and.rhs.699:
  %t2142 = load i32, ptr %slot1632, !dbg !676
  %t2143 = load i32, ptr %slot20, !dbg !676
  %t2144 = icmp ult i32 %t2142, %t2143, !dbg !676
  br label %and.end.700, !dbg !676
and.end.700:
  %t2145 = phi i1 [ false, %while.head.696 ], [ %t2144, %and.rhs.699 ], !dbg !676
  br i1 %t2145, label %while.body.697, label %while.end.698, !dbg !676
while.body.697:
  %t2146 = load i32, ptr %slot1632, !dbg !677
  %t2147 = zext i32 %t2146 to i64, !dbg !677
  %t2148 = getelementptr inbounds i8, ptr %t14, i64 %t2147, !dbg !677
  %t2149 = load i8, ptr %t2148, !dbg !677
  %t2150 = zext i8 %t2149 to i32, !dbg !677
  store i32 %t2150, ptr %slot2151, !dbg !677
  %t2152 = load i32, ptr %slot2151, !dbg !678
  %t2153 = icmp eq i32 %t2152, 32, !dbg !678
  br i1 %t2153, label %or.end.703, label %or.rhs.702, !dbg !678
or.rhs.702:
  %t2154 = load i32, ptr %slot2151, !dbg !678
  %t2155 = icmp eq i32 %t2154, 9, !dbg !678
  br label %or.end.703, !dbg !678
or.end.703:
  %t2156 = phi i1 [ true, %while.body.697 ], [ %t2155, %or.rhs.702 ], !dbg !678
  br i1 %t2156, label %or.end.705, label %or.rhs.704, !dbg !678
or.rhs.704:
  %t2157 = load i32, ptr %slot2151, !dbg !678
  %t2158 = icmp eq i32 %t2157, 10, !dbg !678
  br label %or.end.705, !dbg !678
or.end.705:
  %t2159 = phi i1 [ true, %or.end.703 ], [ %t2158, %or.rhs.704 ], !dbg !678
  br i1 %t2159, label %or.end.707, label %or.rhs.706, !dbg !678
or.rhs.706:
  %t2160 = load i32, ptr %slot2151, !dbg !678
  %t2161 = icmp eq i32 %t2160, 13, !dbg !678
  br label %or.end.707, !dbg !678
or.end.707:
  %t2162 = phi i1 [ true, %or.end.705 ], [ %t2161, %or.rhs.706 ], !dbg !678
  br i1 %t2162, label %if.then.708, label %if.else.709, !dbg !678
if.then.708:
  %t2163 = load i32, ptr %slot1632, !dbg !679
  %t2164 = add i32 %t2163, 1, !dbg !679
  store i32 %t2164, ptr %slot1632, !dbg !679
  br label %if.end.701, !dbg !679
if.else.709:
  store i1 false, ptr %slot2140, !dbg !680
  br label %if.end.701, !dbg !680
if.end.701:
  br label %while.head.696, !dbg !680
while.end.698:
  br label %if.end.687, !dbg !680
if.else.689:
  br label %if.end.687, !dbg !680
if.end.687:
  %t2165 = load i32, ptr %slot1632, !dbg !681
  %t2166 = load i32, ptr %slot20, !dbg !681
  %t2167 = icmp uge i32 %t2165, %t2166, !dbg !681
  br i1 %t2167, label %or.end.712, label %or.rhs.711, !dbg !681
or.rhs.711:
  %t2168 = load i32, ptr %slot1632, !dbg !681
  %t2169 = zext i32 %t2168 to i64, !dbg !681
  %t2170 = icmp uge i64 %t2169, %t15, !dbg !681
  br i1 %t2170, label %lua.raise.713, label %lua.ok.714, !prof !7, !dbg !681
lua.raise.713:
  %t2171 = getelementptr inbounds ptr, ptr %t1, i64 11, !dbg !681
  %rt.raise.2172 = load ptr, ptr %t2171, !invariant.load !8, !dbg !681
  call void %rt.raise.2172(ptr %L, i64 3) nomerge, !dbg !681
  unreachable, !dbg !681
lua.ok.714:
  %t2173 = getelementptr inbounds i8, ptr %t14, i64 %t2169, !dbg !681
  %t2174 = load i8, ptr %t2173, !dbg !681
  %t2175 = zext i8 %t2174 to i32, !dbg !681
  %t2176 = icmp ne i32 %t2175, 34, !dbg !681
  br label %or.end.712, !dbg !681
or.end.712:
  %t2177 = phi i1 [ true, %if.end.687 ], [ %t2176, %lua.ok.714 ], !dbg !681
  br i1 %t2177, label %if.then.715, label %if.else.716, !dbg !681
if.then.715:
  call void @lua_pushvalue(ptr %L, i32 2), !dbg !682
  %t2178 = call i32 @nupp.wrap.u32(double 0x3FF0000000000000), !dbg !682
  %t2179 = uitofp i32 %t2178 to double, !dbg !682
  call void @lua_pushnumber(ptr %L, double %t2179), !dbg !682
  %t2180 = load i32, ptr %slot1632, !dbg !682
  %t2181 = add i32 %t2180, 1, !dbg !682
  %t2182 = uitofp i32 %t2181 to double, !dbg !682
  call void @lua_pushnumber(ptr %L, double %t2182), !dbg !682
  ret i32 3, !dbg !682
if.else.716:
  br label %if.end.710, !dbg !682
if.end.710:
  %t2183 = load i32, ptr %slot1632, !dbg !683
  store i32 %t2183, ptr %slot2184, !dbg !683
  %t2185 = load i32, ptr %slot1636, !dbg !684
  %t2186 = load i32, ptr %slot35, !dbg !684
  %t2187 = icmp uge i32 %t2185, %t2186, !dbg !684
  br i1 %t2187, label %or.end.719, label %or.rhs.718, !dbg !684
or.rhs.718:
  %t2188 = load i32, ptr %slot1636, !dbg !684
  %t2189 = getelementptr inbounds { ptr, i32, i32, i32, i32, [32 x i32] }, ptr %slot27, i32 0, i32 0, !dbg !684
  %t2190 = load ptr, ptr %t2189, !dbg !684
  %t2191 = zext i32 %t2188 to i64, !dbg !684
  %t2192 = getelementptr inbounds i32, ptr %t2190, i64 %t2191, !dbg !684
  %t2193 = load i32, ptr %t2192, !dbg !684
  %t2194 = load i32, ptr %slot2184, !dbg !684
  %t2195 = icmp ne i32 %t2193, %t2194, !dbg !684
  br label %or.end.719, !dbg !684
or.end.719:
  %t2196 = phi i1 [ true, %if.end.710 ], [ %t2195, %or.rhs.718 ], !dbg !684
  br i1 %t2196, label %if.then.720, label %if.else.721, !dbg !684
if.then.720:
  call void @lua_pushvalue(ptr %L, i32 2), !dbg !685
  %t2197 = call i32 @nupp.wrap.u32(double 0x4014000000000000), !dbg !685
  %t2198 = uitofp i32 %t2197 to double, !dbg !685
  call void @lua_pushnumber(ptr %L, double %t2198), !dbg !685
  %t2199 = load i32, ptr %slot1632, !dbg !685
  %t2200 = add i32 %t2199, 1, !dbg !685
  %t2201 = uitofp i32 %t2200 to double, !dbg !685
  call void @lua_pushnumber(ptr %L, double %t2201), !dbg !685
  ret i32 3, !dbg !685
if.else.721:
  br label %if.end.717, !dbg !685
if.end.717:
  %t2202 = load i32, ptr %slot1636, !dbg !686
  %t2203 = add i32 %t2202, 1, !dbg !686
  store i32 %t2203, ptr %slot1636, !dbg !686
  %t2204 = load i32, ptr %slot1636, !dbg !687
  %t2205 = load i32, ptr %slot35, !dbg !687
  %t2206 = icmp uge i32 %t2204, %t2205, !dbg !687
  br i1 %t2206, label %if.then.723, label %if.else.724, !dbg !687
if.then.723:
  call void @lua_pushvalue(ptr %L, i32 2), !dbg !688
  %t2207 = call i32 @nupp.wrap.u32(double 0x3FF0000000000000), !dbg !688
  %t2208 = uitofp i32 %t2207 to double, !dbg !688
  call void @lua_pushnumber(ptr %L, double %t2208), !dbg !688
  %t2209 = load i32, ptr %slot1632, !dbg !688
  %t2210 = add i32 %t2209, 1, !dbg !688
  %t2211 = uitofp i32 %t2210 to double, !dbg !688
  call void @lua_pushnumber(ptr %L, double %t2211), !dbg !688
  ret i32 3, !dbg !688
if.else.724:
  br label %if.end.722, !dbg !688
if.end.722:
  %t2212 = load i32, ptr %slot1636, !dbg !689
  %t2213 = getelementptr inbounds { ptr, i32, i32, i32, i32, [32 x i32] }, ptr %slot27, i32 0, i32 2, !dbg !689
  %t2214 = load i32, ptr %t2213, !dbg !689
  %t2215 = icmp uge i32 %t2212, %t2214, !dbg !689
  br i1 %t2215, label %lua.raise.725, label %lua.ok.726, !prof !7, !dbg !689
lua.raise.725:
  %t2216 = getelementptr inbounds ptr, ptr %t1, i64 11, !dbg !689
  %rt.raise.2217 = load ptr, ptr %t2216, !invariant.load !8, !dbg !689
  call void %rt.raise.2217(ptr %L, i64 7) nomerge, !dbg !689
  unreachable, !dbg !689
lua.ok.726:
  %t2218 = getelementptr inbounds { ptr, i32, i32, i32, i32, [32 x i32] }, ptr %slot27, i32 0, i32 0, !dbg !689
  %t2219 = load ptr, ptr %t2218, !dbg !689
  %t2220 = zext i32 %t2212 to i64, !dbg !689
  %t2221 = getelementptr inbounds i32, ptr %t2219, i64 %t2220, !dbg !689
  %t2222 = load i32, ptr %t2221, !dbg !689
  store i32 %t2222, ptr %slot2223, !dbg !689
  %t2224 = load i32, ptr %slot2223, !dbg !690
  %t2225 = and i32 %t2224, 2147483647, !dbg !690
  store i32 %t2225, ptr %slot2226, !dbg !690
  %t2227 = load i32, ptr %slot2223, !dbg !691
  %t2228 = and i32 %t2227, 2147483648, !dbg !691
  %t2229 = icmp ne i32 %t2228, 0, !dbg !691
  store i1 %t2229, ptr %slot2230, !dbg !691
  %t2231 = load i32, ptr %slot1636, !dbg !692
  %t2232 = add i32 %t2231, 1, !dbg !692
  store i32 %t2232, ptr %slot1636, !dbg !692
  %t2233 = load i32, ptr %slot2184, !dbg !693
  %t2234 = add i32 %t2233, 1, !dbg !693
  store i32 %t2234, ptr %slot2235, !dbg !693
  %t2236 = load i32, ptr %slot2226, !dbg !694
  %t2237 = load i32, ptr %slot2235, !dbg !694
  %t2238 = sub i32 %t2236, %t2237, !dbg !694
  store i32 %t2238, ptr %slot2239, !dbg !694
  %t2240 = load i32, ptr %slot2235, !dbg !695
  %t2241 = zext i32 %t2240 to i64, !dbg !695
  %t2242 = load i32, ptr %slot2239, !dbg !695
  %t2243 = zext i32 %t2242 to i64, !dbg !695
  %t2244 = load i1, ptr %slot2230, !dbg !695
  %t2245 = zext i1 %t2244 to i64, !dbg !695
  %t2246 = getelementptr inbounds ptr, ptr %t1, i64 49, !dbg !695
  %rt.builder_string.2247 = load ptr, ptr %t2246, !invariant.load !8, !dbg !695
  call void %rt.builder_string.2247(ptr %L, ptr %slot1618, ptr %t14, i64 %t15, i64 %t2241, i64 %t2243, i64 %t2245, i64 1, i64 0), !dbg !695
  %t2248 = load i32, ptr %slot2226, !dbg !696
  %t2249 = add i32 %t2248, 1, !dbg !696
  store i32 %t2249, ptr %slot1632, !dbg !696
  store i1 true, ptr %slot2250, !dbg !697
  br label %while.head.727, !dbg !698
while.head.727:
  %t2251 = load i1, ptr %slot2250, !dbg !698
  br i1 %t2251, label %and.rhs.730, label %and.end.731, !dbg !698
and.rhs.730:
  %t2252 = load i32, ptr %slot1632, !dbg !698
  %t2253 = load i32, ptr %slot20, !dbg !698
  %t2254 = icmp ult i32 %t2252, %t2253, !dbg !698
  br label %and.end.731, !dbg !698
and.end.731:
  %t2255 = phi i1 [ false, %while.head.727 ], [ %t2254, %and.rhs.730 ], !dbg !698
  br i1 %t2255, label %while.body.728, label %while.end.729, !dbg !698
while.body.728:
  %t2256 = load i32, ptr %slot1632, !dbg !699
  %t2257 = zext i32 %t2256 to i64, !dbg !699
  %t2258 = getelementptr inbounds i8, ptr %t14, i64 %t2257, !dbg !699
  %t2259 = load i8, ptr %t2258, !dbg !699
  %t2260 = zext i8 %t2259 to i32, !dbg !699
  store i32 %t2260, ptr %slot2261, !dbg !699
  %t2262 = load i32, ptr %slot2261, !dbg !700
  %t2263 = icmp eq i32 %t2262, 32, !dbg !700
  br i1 %t2263, label %or.end.734, label %or.rhs.733, !dbg !700
or.rhs.733:
  %t2264 = load i32, ptr %slot2261, !dbg !700
  %t2265 = icmp eq i32 %t2264, 9, !dbg !700
  br label %or.end.734, !dbg !700
or.end.734:
  %t2266 = phi i1 [ true, %while.body.728 ], [ %t2265, %or.rhs.733 ], !dbg !700
  br i1 %t2266, label %or.end.736, label %or.rhs.735, !dbg !700
or.rhs.735:
  %t2267 = load i32, ptr %slot2261, !dbg !700
  %t2268 = icmp eq i32 %t2267, 10, !dbg !700
  br label %or.end.736, !dbg !700
or.end.736:
  %t2269 = phi i1 [ true, %or.end.734 ], [ %t2268, %or.rhs.735 ], !dbg !700
  br i1 %t2269, label %or.end.738, label %or.rhs.737, !dbg !700
or.rhs.737:
  %t2270 = load i32, ptr %slot2261, !dbg !700
  %t2271 = icmp eq i32 %t2270, 13, !dbg !700
  br label %or.end.738, !dbg !700
or.end.738:
  %t2272 = phi i1 [ true, %or.end.736 ], [ %t2271, %or.rhs.737 ], !dbg !700
  br i1 %t2272, label %if.then.739, label %if.else.740, !dbg !700
if.then.739:
  %t2273 = load i32, ptr %slot1632, !dbg !701
  %t2274 = add i32 %t2273, 1, !dbg !701
  store i32 %t2274, ptr %slot1632, !dbg !701
  br label %if.end.732, !dbg !701
if.else.740:
  store i1 false, ptr %slot2250, !dbg !702
  br label %if.end.732, !dbg !702
if.end.732:
  br label %while.head.727, !dbg !702
while.end.729:
  %t2275 = load i32, ptr %slot1632, !dbg !703
  %t2276 = load i32, ptr %slot20, !dbg !703
  %t2277 = icmp uge i32 %t2275, %t2276, !dbg !703
  br i1 %t2277, label %or.end.743, label %or.rhs.742, !dbg !703
or.rhs.742:
  %t2278 = load i32, ptr %slot1632, !dbg !703
  %t2279 = zext i32 %t2278 to i64, !dbg !703
  %t2280 = icmp uge i64 %t2279, %t15, !dbg !703
  br i1 %t2280, label %lua.raise.744, label %lua.ok.745, !prof !7, !dbg !703
lua.raise.744:
  %t2281 = getelementptr inbounds ptr, ptr %t1, i64 11, !dbg !703
  %rt.raise.2282 = load ptr, ptr %t2281, !invariant.load !8, !dbg !703
  call void %rt.raise.2282(ptr %L, i64 3) nomerge, !dbg !703
  unreachable, !dbg !703
lua.ok.745:
  %t2283 = getelementptr inbounds i8, ptr %t14, i64 %t2279, !dbg !703
  %t2284 = load i8, ptr %t2283, !dbg !703
  %t2285 = zext i8 %t2284 to i32, !dbg !703
  %t2286 = icmp ne i32 %t2285, 58, !dbg !703
  br label %or.end.743, !dbg !703
or.end.743:
  %t2287 = phi i1 [ true, %while.end.729 ], [ %t2286, %lua.ok.745 ], !dbg !703
  br i1 %t2287, label %if.then.746, label %if.else.747, !dbg !703
if.then.746:
  call void @lua_pushvalue(ptr %L, i32 2), !dbg !704
  %t2288 = call i32 @nupp.wrap.u32(double 0x3FF0000000000000), !dbg !704
  %t2289 = uitofp i32 %t2288 to double, !dbg !704
  call void @lua_pushnumber(ptr %L, double %t2289), !dbg !704
  %t2290 = load i32, ptr %slot1632, !dbg !704
  %t2291 = add i32 %t2290, 1, !dbg !704
  %t2292 = uitofp i32 %t2291 to double, !dbg !704
  call void @lua_pushnumber(ptr %L, double %t2292), !dbg !704
  ret i32 3, !dbg !704
if.else.747:
  br label %if.end.741, !dbg !704
if.end.741:
  %t2293 = load i32, ptr %slot1636, !dbg !705
  %t2294 = load i32, ptr %slot35, !dbg !705
  %t2295 = icmp uge i32 %t2293, %t2294, !dbg !705
  br i1 %t2295, label %or.end.750, label %or.rhs.749, !dbg !705
or.rhs.749:
  %t2296 = load i32, ptr %slot1636, !dbg !705
  %t2297 = getelementptr inbounds { ptr, i32, i32, i32, i32, [32 x i32] }, ptr %slot27, i32 0, i32 0, !dbg !705
  %t2298 = load ptr, ptr %t2297, !dbg !705
  %t2299 = zext i32 %t2296 to i64, !dbg !705
  %t2300 = getelementptr inbounds i32, ptr %t2298, i64 %t2299, !dbg !705
  %t2301 = load i32, ptr %t2300, !dbg !705
  %t2302 = load i32, ptr %slot1632, !dbg !705
  %t2303 = icmp ne i32 %t2301, %t2302, !dbg !705
  br label %or.end.750, !dbg !705
or.end.750:
  %t2304 = phi i1 [ true, %if.end.741 ], [ %t2303, %or.rhs.749 ], !dbg !705
  br i1 %t2304, label %if.then.751, label %if.else.752, !dbg !705
if.then.751:
  call void @lua_pushvalue(ptr %L, i32 2), !dbg !706
  %t2305 = call i32 @nupp.wrap.u32(double 0x4014000000000000), !dbg !706
  %t2306 = uitofp i32 %t2305 to double, !dbg !706
  call void @lua_pushnumber(ptr %L, double %t2306), !dbg !706
  %t2307 = load i32, ptr %slot1632, !dbg !706
  %t2308 = add i32 %t2307, 1, !dbg !706
  %t2309 = uitofp i32 %t2308 to double, !dbg !706
  call void @lua_pushnumber(ptr %L, double %t2309), !dbg !706
  ret i32 3, !dbg !706
if.else.752:
  br label %if.end.748, !dbg !706
if.end.748:
  %t2310 = load i32, ptr %slot1632, !dbg !707
  %t2311 = add i32 %t2310, 1, !dbg !707
  store i32 %t2311, ptr %slot1632, !dbg !707
  %t2312 = load i32, ptr %slot1636, !dbg !708
  %t2313 = add i32 %t2312, 1, !dbg !708
  store i32 %t2313, ptr %slot1636, !dbg !708
  store i1 true, ptr %slot1637, !dbg !709
  br label %if.end.669, !dbg !709
if.end.669:
  br label %if.end.535, !dbg !709
if.end.535:
  br label %while.head.518, !dbg !709
while.end.520:
  %t2314 = getelementptr inbounds ptr, ptr %t1, i64 65, !dbg !710
  %rt.builder_finish.2315 = load ptr, ptr %t2314, !invariant.load !8, !dbg !710
  call void %rt.builder_finish.2315(ptr %L, ptr %slot1618), !dbg !710
  %t2316 = call i32 @nupp.wrap.u32(double 0x0000000000000000), !dbg !710
  %t2317 = uitofp i32 %t2316 to double, !dbg !710
  call void @lua_pushnumber(ptr %L, double %t2317), !dbg !710
  %t2318 = call i32 @nupp.wrap.u32(double 0x0000000000000000), !dbg !710
  %t2319 = uitofp i32 %t2318 to double, !dbg !710
  call void @lua_pushnumber(ptr %L, double %t2319), !dbg !710
  ret i32 3, !dbg !710
}

define internal <16 x i8> @ks___nupp_const_decode_fused_f007fffb3d50ef9f__5f5f6e757070436f6e73745f6465636f646546757365645f66303037666666623364353065663966_helper_nibble_table(<16 x i8> %h_a_zero, i32 %h_a_e0, i32 %h_a_e1, i32 %h_a_e2, i32 %h_a_e3, i32 %h_a_e4, i32 %h_a_e5, i32 %h_a_e6, i32 %h_a_e7, i32 %h_a_e8, i32 %h_a_e9, i32 %h_a_e10, i32 %h_a_e11, i32 %h_a_e12, i32 %h_a_e13, i32 %h_a_e14, i32 %h_a_e15) #1 {
entry:
  br label %body
body:
  %t1 = trunc i32 %h_a_e0 to i8
  %t2 = insertelement <16 x i8> %h_a_zero, i8 %t1, i32 0
  %t3 = trunc i32 %h_a_e1 to i8
  %t4 = insertelement <16 x i8> %t2, i8 %t3, i32 1
  %t5 = trunc i32 %h_a_e2 to i8
  %t6 = insertelement <16 x i8> %t4, i8 %t5, i32 2
  %t7 = trunc i32 %h_a_e3 to i8
  %t8 = insertelement <16 x i8> %t6, i8 %t7, i32 3
  %t9 = trunc i32 %h_a_e4 to i8
  %t10 = insertelement <16 x i8> %t8, i8 %t9, i32 4
  %t11 = trunc i32 %h_a_e5 to i8
  %t12 = insertelement <16 x i8> %t10, i8 %t11, i32 5
  %t13 = trunc i32 %h_a_e6 to i8
  %t14 = insertelement <16 x i8> %t12, i8 %t13, i32 6
  %t15 = trunc i32 %h_a_e7 to i8
  %t16 = insertelement <16 x i8> %t14, i8 %t15, i32 7
  %t17 = trunc i32 %h_a_e8 to i8
  %t18 = insertelement <16 x i8> %t16, i8 %t17, i32 8
  %t19 = trunc i32 %h_a_e9 to i8
  %t20 = insertelement <16 x i8> %t18, i8 %t19, i32 9
  %t21 = trunc i32 %h_a_e10 to i8
  %t22 = insertelement <16 x i8> %t20, i8 %t21, i32 10
  %t23 = trunc i32 %h_a_e11 to i8
  %t24 = insertelement <16 x i8> %t22, i8 %t23, i32 11
  %t25 = trunc i32 %h_a_e12 to i8
  %t26 = insertelement <16 x i8> %t24, i8 %t25, i32 12
  %t27 = trunc i32 %h_a_e13 to i8
  %t28 = insertelement <16 x i8> %t26, i8 %t27, i32 13
  %t29 = trunc i32 %h_a_e14 to i8
  %t30 = insertelement <16 x i8> %t28, i8 %t29, i32 14
  %t31 = trunc i32 %h_a_e15 to i8
  %t32 = insertelement <16 x i8> %t30, i8 %t31, i32 15
  ret <16 x i8> %t32
}

define internal i32 @ks_db5c9457e129530e___nupp_const_decode_fused_f007fffb3d50ef9f__5f5f6e757070436f6e73745f6465636f646546757365645f66303037666666623364353065663966__neon_lua(ptr %L) #0 !dbg !711 {
entry:
  %slot6 = alloca i64, align 8
  %slot7 = alloca ptr, align 8
  %slot20 = alloca i32, align 4
  %slot27 = alloca { ptr, i32, i32, i32, i32, [32 x i32] }, align 8
  %slot33 = alloca i32, align 4
  %slot35 = alloca i32, align 4
  %slot36 = alloca i1, align 4
  %slot37 = alloca i1, align 4
  %slot38 = alloca i1, align 4
  %slot39 = alloca i1, align 4
  %slot41 = alloca i32, align 4
  %slot43 = alloca i32, align 4
  %slot45 = alloca i32, align 4
  %slot46 = alloca i1, align 4
  %slot48 = alloca i32, align 4
  %slot49 = alloca i1, align 4
  %slot50 = alloca i1, align 4
  %slot55 = alloca i64, align 8
  %slot56 = alloca i1, align 4
  %slot68 = alloca i64, align 8
  %slot70 = alloca i32, align 4
  %slot168 = alloca <16 x i8>
  %slot196 = alloca <16 x i1>
  %slot210 = alloca <16 x i1>
  %slot224 = alloca <16 x i1>
  %slot237 = alloca <16 x i1>
  %slot238 = alloca i1, align 4
  %slot249 = alloca <16 x i1>
  %slot357 = alloca <16 x i8>
  %slot361 = alloca <16 x i8>
  %slot365 = alloca <16 x i8>
  %slot369 = alloca <16 x i8>
  %slot374 = alloca <16 x i8>
  %slot377 = alloca <16 x i8>
  %slot380 = alloca <16 x i8>
  %slot383 = alloca <16 x i8>
  %slot430 = alloca <16 x i8>
  %slot453 = alloca <16 x i8>
  %slot482 = alloca i32, align 4
  %slot483 = alloca i1, align 4
  %slot502 = alloca i32, align 4
  %slot520 = alloca i32, align 4
  %slot562 = alloca i32, align 4
  %slot603 = alloca i32, align 4
  %slot615 = alloca i32, align 4
  %slot624 = alloca i32, align 4
  %slot644 = alloca i1, align 4
  %slot677 = alloca i1, align 4
  %slot752 = alloca i1, align 4
  %slot760 = alloca i32, align 4
  %slot812 = alloca i1, align 4
  %slot1614 = alloca i32, align 4
  %slot1618 = alloca [4096 x i8], align 16
  %slot1632 = alloca i32, align 4
  %slot1636 = alloca i32, align 4
  %slot1637 = alloca i1, align 4
  %slot1638 = alloca i1, align 4
  %slot1640 = alloca i32, align 4
  %slot1643 = alloca i1, align 4
  %slot1678 = alloca i32, align 4
  %slot1680 = alloca i32, align 4
  %slot1682 = alloca i32, align 4
  %slot1684 = alloca i32, align 4
  %slot1686 = alloca i32, align 4
  %slot1688 = alloca i32, align 4
  %slot1701 = alloca i32, align 4
  %slot1726 = alloca i32, align 4
  %slot1729 = alloca i32, align 4
  %slot1794 = alloca i32, align 4
  %slot1800 = alloca i32, align 4
  %slot1809 = alloca i32, align 4
  %slot1811 = alloca i32, align 4
  %slot1812 = alloca i32, align 4
  %slot1845 = alloca i32, align 4
  %slot1851 = alloca i32, align 4
  %slot1860 = alloca i32, align 4
  %slot1862 = alloca i32, align 4
  %slot1863 = alloca i32, align 4
  %slot1899 = alloca i32, align 4
  %slot1905 = alloca i32, align 4
  %slot1914 = alloca i32, align 4
  %slot1916 = alloca i32, align 4
  %slot1917 = alloca i32, align 4
  %slot1960 = alloca i32, align 4
  %slot2036 = alloca i32, align 4
  %slot2053 = alloca i32, align 4
  %slot2055 = alloca i32, align 4
  %slot2058 = alloca i32, align 4
  %slot2062 = alloca i1, align 4
  %slot2074 = alloca i1, align 4
  %slot2140 = alloca i1, align 4
  %slot2151 = alloca i32, align 4
  %slot2184 = alloca i32, align 4
  %slot2223 = alloca i32, align 4
  %slot2226 = alloca i32, align 4
  %slot2230 = alloca i1, align 4
  %slot2235 = alloca i32, align 4
  %slot2239 = alloca i32, align 4
  %slot2250 = alloca i1, align 4
  %slot2261 = alloca i32, align 4
  br label %body
body:
  %t1 = load ptr, ptr @ks.rt, !dbg !712
  %t2 = call i32 @lua_checkstack(ptr %L, i32 10), !dbg !712
  %t3 = icmp eq i32 %t2, 0, !dbg !712
  br i1 %t3, label %lua.raise.1, label %lua.ok.2, !prof !7, !dbg !712
lua.raise.1:
  %t4 = getelementptr inbounds ptr, ptr %t1, i64 11, !dbg !712
  %rt.raise.5 = load ptr, ptr %t4, !invariant.load !8, !dbg !712
  call void %rt.raise.5(ptr %L, i64 1) nomerge, !dbg !712
  unreachable, !dbg !712
lua.ok.2:
  %t8 = call i32 @lua_type(ptr %L, i32 1), !dbg !712
  %t9 = icmp eq i32 %t8, 4, !dbg !712
  br i1 %t9, label %lua.string.3, label %lua.buffer.4, !dbg !712
lua.string.3:
  %t10 = call ptr @luaL_checklstring(ptr %L, i32 1, ptr %slot6), !dbg !712
  store ptr %t10, ptr %slot7, !dbg !712
  br label %lua.bytes.5, !dbg !712
lua.buffer.4:
  %t11 = getelementptr inbounds ptr, ptr %t1, i64 14, !dbg !712
  %rt.bytes.12 = load ptr, ptr %t11, !invariant.load !8, !dbg !712
  %t13 = call ptr %rt.bytes.12(ptr %L, i64 1, ptr %slot6), !dbg !712
  store ptr %t13, ptr %slot7, !dbg !712
  br label %lua.bytes.5, !dbg !712
lua.bytes.5:
  %t14 = load ptr, ptr %slot7, !dbg !712
  %t15 = load i64, ptr %slot6, !dbg !712
  %t16 = icmp ugt i64 %t15, 4294967295, !dbg !713
  br i1 %t16, label %lua.raise.6, label %lua.ok.7, !prof !7, !dbg !713
lua.raise.6:
  %t17 = getelementptr inbounds ptr, ptr %t1, i64 11, !dbg !713
  %rt.raise.18 = load ptr, ptr %t17, !invariant.load !8, !dbg !713
  call void %rt.raise.18(ptr %L, i64 2) nomerge, !dbg !713
  unreachable, !dbg !713
lua.ok.7:
  %t19 = trunc i64 %t15 to i32, !dbg !713
  store i32 %t19, ptr %slot20, !dbg !713
  %t21 = load i32, ptr %slot20, !dbg !714
  %t22 = icmp ult i32 2147483647, %t21, !dbg !714
  br i1 %t22, label %if.then.9, label %if.else.10, !dbg !714
if.then.9:
  call void @lua_pushvalue(ptr %L, i32 2), !dbg !715
  %t23 = call i32 @nupp.wrap.u32(double 0x4014000000000000), !dbg !715
  %t24 = uitofp i32 %t23 to double, !dbg !715
  call void @lua_pushnumber(ptr %L, double %t24), !dbg !715
  %t25 = call i32 @nupp.wrap.u32(double 0x3FF0000000000000), !dbg !715
  %t26 = uitofp i32 %t25 to double, !dbg !715
  call void @lua_pushnumber(ptr %L, double %t26), !dbg !715
  ret i32 3, !dbg !715
if.else.10:
  br label %if.end.8, !dbg !715
if.end.8:
  %t28 = load i32, ptr %slot20, !dbg !716
  %t29 = zext i32 %t28 to i64, !dbg !716
  %t30 = getelementptr inbounds ptr, ptr %t1, i64 29, !dbg !716
  %rt.scratch_u32.31 = load ptr, ptr %t30, !invariant.load !8, !dbg !716
  call void %rt.scratch_u32.31(ptr %L, ptr %slot27, i64 %t29, ptr @ks.key.ks_db5c9457e129530e___nupp_const_decode_fused_f007fffb3d50ef9f__5f5f6e757070436f6e73745f6465636f646546757365645f66303037666666623364353065663966.v2_tape), !dbg !716
  %t32 = call i32 @nupp.wrap.u32(double 0x0000000000000000), !dbg !717
  store i32 %t32, ptr %slot33, !dbg !717
  %t34 = call i32 @nupp.wrap.u32(double 0x0000000000000000), !dbg !718
  store i32 %t34, ptr %slot35, !dbg !718
  store i1 false, ptr %slot36, !dbg !719
  store i1 false, ptr %slot37, !dbg !720
  store i1 false, ptr %slot38, !dbg !721
  store i1 false, ptr %slot39, !dbg !722
  %t40 = call i32 @nupp.wrap.u32(double 0x0000000000000000), !dbg !723
  store i32 %t40, ptr %slot41, !dbg !723
  %t42 = call i32 @nupp.wrap.u32(double 0x0000000000000000), !dbg !724
  store i32 %t42, ptr %slot43, !dbg !724
  %t44 = call i32 @nupp.wrap.u32(double 0x0000000000000000), !dbg !725
  store i32 %t44, ptr %slot45, !dbg !725
  store i1 false, ptr %slot46, !dbg !726
  %t47 = call i32 @nupp.wrap.u32(double 0x0000000000000000), !dbg !727
  store i32 %t47, ptr %slot48, !dbg !727
  store i1 false, ptr %slot49, !dbg !728
  store i1 false, ptr %slot50, !dbg !729
  %t51 = call i64 @llvm.fptosi.sat.i64.f64(double 0x3FF0000000000000), !dbg !730
  %t52 = call i64 @llvm.fptoui.sat.i64.f64(double 0x3FF0000000000000), !dbg !730
  %t53 = fcmp olt double 0x3FF0000000000000, 0.0, !dbg !730
  %t54 = select i1 %t53, i64 %t51, i64 %t52, !dbg !730
  store i64 %t54, ptr %slot55, !dbg !730
  store i1 false, ptr %slot56, !dbg !731
  %t57 = icmp ule i64 %t15, 4294967295, !dbg !732
  br i1 %t57, label %cursors.wide.11, label %cursors.narrow.12, !dbg !732
cursors.wide.11:
  br label %while.head.14, !dbg !732
while.head.14:
  %t58 = load i32, ptr %slot33, !dbg !732
  %t59 = load i32, ptr %slot20, !dbg !732
  %t60 = icmp ult i32 %t58, %t59, !dbg !732
  br i1 %t60, label %or.end.18, label %or.rhs.17, !dbg !732
or.rhs.17:
  %t61 = load i1, ptr %slot49, !dbg !732
  %t62 = xor i1 %t61, true, !dbg !732
  br label %or.end.18, !dbg !732
or.end.18:
  %t63 = phi i1 [ true, %while.head.14 ], [ %t62, %or.rhs.17 ], !dbg !732
  br i1 %t63, label %while.body.15, label %while.end.16, !dbg !732
while.body.15:
  %t64 = call i64 @llvm.fptosi.sat.i64.f64(double 0x0000000000000000), !dbg !733
  %t65 = call i64 @llvm.fptoui.sat.i64.f64(double 0x0000000000000000), !dbg !733
  %t66 = fcmp olt double 0x0000000000000000, 0.0, !dbg !733
  %t67 = select i1 %t66, i64 %t64, i64 %t65, !dbg !733
  store i64 %t67, ptr %slot68, !dbg !733
  %t69 = call i32 @nupp.wrap.u32(double 0x0000000000000000), !dbg !734
  store i32 %t69, ptr %slot70, !dbg !734
  br i1 true, label %if.then.20, label %if.else.21, !dbg !735
if.then.20:
  %t71 = load i1, ptr %slot56, !dbg !736
  %t72 = xor i1 %t71, true, !dbg !736
  br i1 %t72, label %and.rhs.23, label %and.end.24, !dbg !736
and.rhs.23:
  %t73 = load i32, ptr %slot33, !dbg !736
  %t74 = zext i32 %t73 to i64, !dbg !736
  %t75 = zext i32 16 to i64, !dbg !736
  %t76 = add i64 %t74, %t75, !dbg !736
  %t77 = load i32, ptr %slot20, !dbg !736
  %t78 = zext i32 %t77 to i64, !dbg !736
  %t79 = icmp ule i64 %t76, %t78, !dbg !736
  br label %and.end.24, !dbg !736
and.end.24:
  %t80 = phi i1 [ false, %if.then.20 ], [ %t79, %and.rhs.23 ], !dbg !736
  br i1 %t80, label %if.then.25, label %if.else.26, !dbg !736
if.then.25:
  %t81 = load i32, ptr %slot33, !dbg !737
  %t82 = zext i32 %t81 to i64, !dbg !737
  %t83 = add nuw i64 %t82, 0, !dbg !737
  %t84 = getelementptr inbounds nuw i8, ptr %t14, i64 %t83, !dbg !737
  br i1 true, label %simd.yes.27, label %simd.no.28, !dbg !737
simd.yes.27:
  %t85 = load <16 x i8>, ptr %t84, align 1, !dbg !737
  br label %simd.join.29, !dbg !737
simd.no.28:
  %t86 = load i32, ptr %slot33, !dbg !737
  %t87 = add i32 %t86, 1, !dbg !737
  %t88 = zext i32 %t87 to i64, !dbg !737
  %t89 = icmp ne i64 %t88, 0, !dbg !737
  %t90 = sub i64 %t88, 1, !dbg !737
  %t91 = select i1 %t89, i64 %t90, i64 -1, !dbg !737
  %t92 = icmp ult i64 %t91, %t15, !dbg !737
  %t93 = sub i64 %t15, %t91, !dbg !737
  %t94 = icmp ult i64 %t93, 16, !dbg !737
  %t95 = select i1 %t94, i64 %t93, i64 16, !dbg !737
  %t96 = select i1 %t92, i64 %t95, i64 0, !dbg !737
  %t97 = trunc i64 %t96 to i32, !dbg !737
  %t98 = select i1 %t92, i64 %t91, i64 0, !dbg !737
  %t99 = getelementptr inbounds i8, ptr %t14, i64 %t98, !dbg !737
  %t100 = icmp eq i32 %t97, 16, !dbg !737
  br i1 %t100, label %simd.yes.30, label %simd.no.31, !dbg !737
simd.yes.30:
  %t101 = load <16 x i8>, ptr %t99, align 1, !dbg !737
  br label %simd.join.32, !dbg !737
simd.no.31:
  switch i32 %t97, label %tail.done.49 [ i32 1, label %tail.lane.33 i32 2, label %tail.lane.34 i32 3, label %tail.lane.35 i32 4, label %tail.lane.36 i32 5, label %tail.lane.37 i32 6, label %tail.lane.38 i32 7, label %tail.lane.39 i32 8, label %tail.lane.40 i32 9, label %tail.lane.41 i32 10, label %tail.lane.42 i32 11, label %tail.lane.43 i32 12, label %tail.lane.44 i32 13, label %tail.lane.45 i32 14, label %tail.lane.46 i32 15, label %tail.lane.47 i32 16, label %tail.lane.48 ], !dbg !737
tail.lane.48:
  %t102 = getelementptr inbounds i8, ptr %t99, i64 15, !dbg !737
  %t103 = load i8, ptr %t102, align 1, !dbg !737
  %t104 = insertelement <16 x i8> zeroinitializer, i8 %t103, i32 15, !dbg !737
  br label %tail.lane.47, !dbg !737
tail.lane.47:
  %t105 = phi <16 x i8> [ zeroinitializer, %simd.no.31 ], [ %t104, %tail.lane.48 ], !dbg !737
  %t106 = getelementptr inbounds i8, ptr %t99, i64 14, !dbg !737
  %t107 = load i8, ptr %t106, align 1, !dbg !737
  %t108 = insertelement <16 x i8> %t105, i8 %t107, i32 14, !dbg !737
  br label %tail.lane.46, !dbg !737
tail.lane.46:
  %t109 = phi <16 x i8> [ zeroinitializer, %simd.no.31 ], [ %t108, %tail.lane.47 ], !dbg !737
  %t110 = getelementptr inbounds i8, ptr %t99, i64 13, !dbg !737
  %t111 = load i8, ptr %t110, align 1, !dbg !737
  %t112 = insertelement <16 x i8> %t109, i8 %t111, i32 13, !dbg !737
  br label %tail.lane.45, !dbg !737
tail.lane.45:
  %t113 = phi <16 x i8> [ zeroinitializer, %simd.no.31 ], [ %t112, %tail.lane.46 ], !dbg !737
  %t114 = getelementptr inbounds i8, ptr %t99, i64 12, !dbg !737
  %t115 = load i8, ptr %t114, align 1, !dbg !737
  %t116 = insertelement <16 x i8> %t113, i8 %t115, i32 12, !dbg !737
  br label %tail.lane.44, !dbg !737
tail.lane.44:
  %t117 = phi <16 x i8> [ zeroinitializer, %simd.no.31 ], [ %t116, %tail.lane.45 ], !dbg !737
  %t118 = getelementptr inbounds i8, ptr %t99, i64 11, !dbg !737
  %t119 = load i8, ptr %t118, align 1, !dbg !737
  %t120 = insertelement <16 x i8> %t117, i8 %t119, i32 11, !dbg !737
  br label %tail.lane.43, !dbg !737
tail.lane.43:
  %t121 = phi <16 x i8> [ zeroinitializer, %simd.no.31 ], [ %t120, %tail.lane.44 ], !dbg !737
  %t122 = getelementptr inbounds i8, ptr %t99, i64 10, !dbg !737
  %t123 = load i8, ptr %t122, align 1, !dbg !737
  %t124 = insertelement <16 x i8> %t121, i8 %t123, i32 10, !dbg !737
  br label %tail.lane.42, !dbg !737
tail.lane.42:
  %t125 = phi <16 x i8> [ zeroinitializer, %simd.no.31 ], [ %t124, %tail.lane.43 ], !dbg !737
  %t126 = getelementptr inbounds i8, ptr %t99, i64 9, !dbg !737
  %t127 = load i8, ptr %t126, align 1, !dbg !737
  %t128 = insertelement <16 x i8> %t125, i8 %t127, i32 9, !dbg !737
  br label %tail.lane.41, !dbg !737
tail.lane.41:
  %t129 = phi <16 x i8> [ zeroinitializer, %simd.no.31 ], [ %t128, %tail.lane.42 ], !dbg !737
  %t130 = getelementptr inbounds i8, ptr %t99, i64 8, !dbg !737
  %t131 = load i8, ptr %t130, align 1, !dbg !737
  %t132 = insertelement <16 x i8> %t129, i8 %t131, i32 8, !dbg !737
  br label %tail.lane.40, !dbg !737
tail.lane.40:
  %t133 = phi <16 x i8> [ zeroinitializer, %simd.no.31 ], [ %t132, %tail.lane.41 ], !dbg !737
  %t134 = getelementptr inbounds i8, ptr %t99, i64 7, !dbg !737
  %t135 = load i8, ptr %t134, align 1, !dbg !737
  %t136 = insertelement <16 x i8> %t133, i8 %t135, i32 7, !dbg !737
  br label %tail.lane.39, !dbg !737
tail.lane.39:
  %t137 = phi <16 x i8> [ zeroinitializer, %simd.no.31 ], [ %t136, %tail.lane.40 ], !dbg !737
  %t138 = getelementptr inbounds i8, ptr %t99, i64 6, !dbg !737
  %t139 = load i8, ptr %t138, align 1, !dbg !737
  %t140 = insertelement <16 x i8> %t137, i8 %t139, i32 6, !dbg !737
  br label %tail.lane.38, !dbg !737
tail.lane.38:
  %t141 = phi <16 x i8> [ zeroinitializer, %simd.no.31 ], [ %t140, %tail.lane.39 ], !dbg !737
  %t142 = getelementptr inbounds i8, ptr %t99, i64 5, !dbg !737
  %t143 = load i8, ptr %t142, align 1, !dbg !737
  %t144 = insertelement <16 x i8> %t141, i8 %t143, i32 5, !dbg !737
  br label %tail.lane.37, !dbg !737
tail.lane.37:
  %t145 = phi <16 x i8> [ zeroinitializer, %simd.no.31 ], [ %t144, %tail.lane.38 ], !dbg !737
  %t146 = getelementptr inbounds i8, ptr %t99, i64 4, !dbg !737
  %t147 = load i8, ptr %t146, align 1, !dbg !737
  %t148 = insertelement <16 x i8> %t145, i8 %t147, i32 4, !dbg !737
  br label %tail.lane.36, !dbg !737
tail.lane.36:
  %t149 = phi <16 x i8> [ zeroinitializer, %simd.no.31 ], [ %t148, %tail.lane.37 ], !dbg !737
  %t150 = getelementptr inbounds i8, ptr %t99, i64 3, !dbg !737
  %t151 = load i8, ptr %t150, align 1, !dbg !737
  %t152 = insertelement <16 x i8> %t149, i8 %t151, i32 3, !dbg !737
  br label %tail.lane.35, !dbg !737
tail.lane.35:
  %t153 = phi <16 x i8> [ zeroinitializer, %simd.no.31 ], [ %t152, %tail.lane.36 ], !dbg !737
  %t154 = getelementptr inbounds i8, ptr %t99, i64 2, !dbg !737
  %t155 = load i8, ptr %t154, align 1, !dbg !737
  %t156 = insertelement <16 x i8> %t153, i8 %t155, i32 2, !dbg !737
  br label %tail.lane.34, !dbg !737
tail.lane.34:
  %t157 = phi <16 x i8> [ zeroinitializer, %simd.no.31 ], [ %t156, %tail.lane.35 ], !dbg !737
  %t158 = getelementptr inbounds i8, ptr %t99, i64 1, !dbg !737
  %t159 = load i8, ptr %t158, align 1, !dbg !737
  %t160 = insertelement <16 x i8> %t157, i8 %t159, i32 1, !dbg !737
  br label %tail.lane.33, !dbg !737
tail.lane.33:
  %t161 = phi <16 x i8> [ zeroinitializer, %simd.no.31 ], [ %t160, %tail.lane.34 ], !dbg !737
  %t162 = getelementptr inbounds i8, ptr %t99, i64 0, !dbg !737
  %t163 = load i8, ptr %t162, align 1, !dbg !737
  %t164 = insertelement <16 x i8> %t161, i8 %t163, i32 0, !dbg !737
  br label %tail.done.49, !dbg !737
tail.done.49:
  %t165 = phi <16 x i8> [ zeroinitializer, %simd.no.31 ], [ %t164, %tail.lane.33 ], !dbg !737
  br label %simd.join.32, !dbg !737
simd.join.32:
  %t166 = phi <16 x i8> [ %t101, %simd.yes.30 ], [ %t165, %tail.done.49 ], !dbg !737
  br label %simd.join.29, !dbg !737
simd.join.29:
  %t167 = phi <16 x i8> [ %t85, %simd.yes.27 ], [ %t166, %simd.join.32 ], !dbg !737
  store <16 x i8> %t167, ptr %slot168, !dbg !737
  %t169 = load <16 x i8>, ptr %slot168, !dbg !738
  %t170 = call i32 @nupp.wrap.u32(double 0x405EC00000000000), !dbg !738
  %t171 = trunc i32 %t170 to i8, !dbg !738
  %t172 = insertelement <16 x i8> poison, i8 %t171, i64 0, !dbg !738
  %t173 = shufflevector <16 x i8> %t172, <16 x i8> poison, <16 x i32> zeroinitializer, !dbg !738
  %t174 = icmp eq <16 x i8> %t169, %t173, !dbg !738
  %t175 = load <16 x i8>, ptr %slot168, !dbg !738
  %t176 = call i32 @nupp.wrap.u32(double 0x405F400000000000), !dbg !738
  %t177 = trunc i32 %t176 to i8, !dbg !738
  %t178 = insertelement <16 x i8> poison, i8 %t177, i64 0, !dbg !738
  %t179 = shufflevector <16 x i8> %t178, <16 x i8> poison, <16 x i32> zeroinitializer, !dbg !738
  %t180 = icmp eq <16 x i8> %t175, %t179, !dbg !738
  %t181 = or <16 x i1> %t174, %t180, !dbg !738
  %t182 = load <16 x i8>, ptr %slot168, !dbg !738
  %t183 = call i32 @nupp.wrap.u32(double 0x4056C00000000000), !dbg !738
  %t184 = trunc i32 %t183 to i8, !dbg !738
  %t185 = insertelement <16 x i8> poison, i8 %t184, i64 0, !dbg !738
  %t186 = shufflevector <16 x i8> %t185, <16 x i8> poison, <16 x i32> zeroinitializer, !dbg !738
  %t187 = icmp eq <16 x i8> %t182, %t186, !dbg !738
  %t188 = or <16 x i1> %t181, %t187, !dbg !738
  %t189 = load <16 x i8>, ptr %slot168, !dbg !738
  %t190 = call i32 @nupp.wrap.u32(double 0x4057400000000000), !dbg !738
  %t191 = trunc i32 %t190 to i8, !dbg !738
  %t192 = insertelement <16 x i8> poison, i8 %t191, i64 0, !dbg !738
  %t193 = shufflevector <16 x i8> %t192, <16 x i8> poison, <16 x i32> zeroinitializer, !dbg !738
  %t194 = icmp eq <16 x i8> %t189, %t193, !dbg !738
  %t195 = or <16 x i1> %t188, %t194, !dbg !738
  store <16 x i1> %t195, ptr %slot196, !dbg !738
  %t197 = load <16 x i8>, ptr %slot168, !dbg !739
  %t198 = call i32 @nupp.wrap.u32(double 0x404D000000000000), !dbg !739
  %t199 = trunc i32 %t198 to i8, !dbg !739
  %t200 = insertelement <16 x i8> poison, i8 %t199, i64 0, !dbg !739
  %t201 = shufflevector <16 x i8> %t200, <16 x i8> poison, <16 x i32> zeroinitializer, !dbg !739
  %t202 = icmp eq <16 x i8> %t197, %t201, !dbg !739
  %t203 = load <16 x i8>, ptr %slot168, !dbg !739
  %t204 = call i32 @nupp.wrap.u32(double 0x4046000000000000), !dbg !739
  %t205 = trunc i32 %t204 to i8, !dbg !739
  %t206 = insertelement <16 x i8> poison, i8 %t205, i64 0, !dbg !739
  %t207 = shufflevector <16 x i8> %t206, <16 x i8> poison, <16 x i32> zeroinitializer, !dbg !739
  %t208 = icmp eq <16 x i8> %t203, %t207, !dbg !739
  %t209 = or <16 x i1> %t202, %t208, !dbg !739
  store <16 x i1> %t209, ptr %slot210, !dbg !739
  %t211 = load <16 x i8>, ptr %slot168, !dbg !740
  %t212 = call i32 @nupp.wrap.u32(double 0x4041000000000000), !dbg !740
  %t213 = trunc i32 %t212 to i8, !dbg !740
  %t214 = insertelement <16 x i8> poison, i8 %t213, i64 0, !dbg !740
  %t215 = shufflevector <16 x i8> %t214, <16 x i8> poison, <16 x i32> zeroinitializer, !dbg !740
  %t216 = icmp eq <16 x i8> %t211, %t215, !dbg !740
  %t217 = load <16 x i8>, ptr %slot168, !dbg !740
  %t218 = call i32 @nupp.wrap.u32(double 0x4057000000000000), !dbg !740
  %t219 = trunc i32 %t218 to i8, !dbg !740
  %t220 = insertelement <16 x i8> poison, i8 %t219, i64 0, !dbg !740
  %t221 = shufflevector <16 x i8> %t220, <16 x i8> poison, <16 x i32> zeroinitializer, !dbg !740
  %t222 = icmp eq <16 x i8> %t217, %t221, !dbg !740
  %t223 = or <16 x i1> %t216, %t222, !dbg !740
  store <16 x i1> %t223, ptr %slot224, !dbg !740
  %t225 = load <16 x i1>, ptr %slot196, !dbg !741
  %t226 = load <16 x i1>, ptr %slot210, !dbg !741
  %t227 = or <16 x i1> %t225, %t226, !dbg !741
  %t228 = load <16 x i1>, ptr %slot224, !dbg !741
  %t229 = or <16 x i1> %t227, %t228, !dbg !741
  %t230 = load <16 x i8>, ptr %slot168, !dbg !741
  %t231 = call i32 @nupp.wrap.u32(double 0x4040000000000000), !dbg !741
  %t232 = trunc i32 %t231 to i8, !dbg !741
  %t233 = insertelement <16 x i8> poison, i8 %t232, i64 0, !dbg !741
  %t234 = shufflevector <16 x i8> %t233, <16 x i8> poison, <16 x i32> zeroinitializer, !dbg !741
  %t235 = icmp ult <16 x i8> %t230, %t234, !dbg !741
  %t236 = or <16 x i1> %t229, %t235, !dbg !741
  store <16 x i1> %t236, ptr %slot237, !dbg !741
  store i1 false, ptr %slot238, !dbg !742
  %t239 = load i1, ptr %slot50, !dbg !743
  br i1 %t239, label %if.then.51, label %if.else.52, !dbg !743
if.then.51:
  %t240 = load <16 x i1>, ptr %slot237, !dbg !744
  %t241 = bitcast <16 x i1> %t240 to i16, !dbg !744
  %t242 = zext i16 %t241 to i64, !dbg !744
  store i64 %t242, ptr %slot68, !dbg !744
  store i1 true, ptr %slot238, !dbg !745
  br label %if.end.50, !dbg !745
if.else.52:
  %t243 = load <16 x i8>, ptr %slot168, !dbg !746
  %t244 = call i32 @nupp.wrap.u32(double 0x4060000000000000), !dbg !746
  %t245 = trunc i32 %t244 to i8, !dbg !746
  %t246 = insertelement <16 x i8> poison, i8 %t245, i64 0, !dbg !746
  %t247 = shufflevector <16 x i8> %t246, <16 x i8> poison, <16 x i32> zeroinitializer, !dbg !746
  %t248 = icmp uge <16 x i8> %t243, %t247, !dbg !746
  store <16 x i1> %t248, ptr %slot249, !dbg !746
  %t250 = load <16 x i1>, ptr %slot237, !dbg !747
  %t251 = load <16 x i1>, ptr %slot249, !dbg !747
  %t252 = or <16 x i1> %t250, %t251, !dbg !747
  %t253 = bitcast <16 x i1> %t252 to i16, !dbg !747
  %t254 = zext i16 %t253 to i64, !dbg !747
  store i64 %t254, ptr %slot68, !dbg !747
  %t255 = load i64, ptr %slot68, !dbg !748
  %t256 = call i64 @llvm.fptosi.sat.i64.f64(double 0x0000000000000000), !dbg !748
  %t257 = call i64 @llvm.fptoui.sat.i64.f64(double 0x0000000000000000), !dbg !748
  %t258 = fcmp olt double 0x0000000000000000, 0.0, !dbg !748
  %t259 = select i1 %t258, i64 %t256, i64 %t257, !dbg !748
  %t260 = icmp ne i64 %t255, %t259, !dbg !748
  br i1 %t260, label %if.then.54, label %if.else.55, !dbg !748
if.then.54:
  %t261 = load <16 x i1>, ptr %slot249, !dbg !749
  %t262 = sext <16 x i1> %t261 to <16 x i8>, !dbg !749
  %t263 = call <16 x i8> asm "", "=w,0"(<16 x i8> %t262), !dbg !749
  %t264 = bitcast <16 x i8> %t263 to <4 x i32>, !dbg !749
  %t265 = shufflevector <4 x i32> %t264, <4 x i32> poison, <4 x i32> <i32 0, i32 1, i32 2, i32 3>, !dbg !749
  %t266 = call <4 x i32> @llvm.aarch64.neon.umaxp.v4i32(<4 x i32> %t265, <4 x i32> %t265), !dbg !749
  %t267 = bitcast <4 x i32> %t266 to <2 x i64>, !dbg !749
  %t268 = extractelement <2 x i64> %t267, i32 0, !dbg !749
  %t269 = icmp ne i64 %t268, 0, !dbg !749
  store i1 %t269, ptr %slot238, !dbg !749
  %t270 = load i1, ptr %slot238, !dbg !750
  br i1 %t270, label %if.then.57, label %if.else.58, !dbg !750
if.then.57:
  %t271 = load <16 x i1>, ptr %slot237, !dbg !751
  %t272 = bitcast <16 x i1> %t271 to i16, !dbg !751
  %t273 = zext i16 %t272 to i64, !dbg !751
  store i64 %t273, ptr %slot68, !dbg !751
  br label %if.end.56, !dbg !751
if.else.58:
  br label %if.end.56, !dbg !751
if.end.56:
  br label %if.end.53, !dbg !751
if.else.55:
  br label %if.end.53, !dbg !751
if.end.53:
  br label %if.end.50, !dbg !751
if.end.50:
  %t274 = load i1, ptr %slot238, !dbg !752
  br i1 %t274, label %if.then.60, label %if.else.61, !dbg !752
if.then.60:
  %t275 = load i32, ptr %slot33, !dbg !753
  %t276 = sub i32 %t275, 16, !dbg !753
  %t277 = add i32 %t276, 1, !dbg !753
  %t278 = zext i32 %t277 to i64, !dbg !753
  %t279 = icmp ne i64 %t278, 0, !dbg !753
  %t280 = sub i64 %t278, 1, !dbg !753
  %t281 = select i1 %t279, i64 %t280, i64 -1, !dbg !753
  %t282 = icmp ult i64 %t281, %t15, !dbg !753
  %t283 = sub i64 %t15, %t281, !dbg !753
  %t284 = icmp ult i64 %t283, 16, !dbg !753
  %t285 = select i1 %t284, i64 %t283, i64 16, !dbg !753
  %t286 = select i1 %t282, i64 %t285, i64 0, !dbg !753
  %t287 = trunc i64 %t286 to i32, !dbg !753
  %t288 = select i1 %t282, i64 %t281, i64 0, !dbg !753
  %t289 = getelementptr inbounds i8, ptr %t14, i64 %t288, !dbg !753
  %t290 = icmp eq i32 %t287, 16, !dbg !753
  br i1 %t290, label %simd.yes.62, label %simd.no.63, !dbg !753
simd.yes.62:
  %t291 = load <16 x i8>, ptr %t289, align 1, !dbg !753
  br label %simd.join.64, !dbg !753
simd.no.63:
  switch i32 %t287, label %tail.done.81 [ i32 1, label %tail.lane.65 i32 2, label %tail.lane.66 i32 3, label %tail.lane.67 i32 4, label %tail.lane.68 i32 5, label %tail.lane.69 i32 6, label %tail.lane.70 i32 7, label %tail.lane.71 i32 8, label %tail.lane.72 i32 9, label %tail.lane.73 i32 10, label %tail.lane.74 i32 11, label %tail.lane.75 i32 12, label %tail.lane.76 i32 13, label %tail.lane.77 i32 14, label %tail.lane.78 i32 15, label %tail.lane.79 i32 16, label %tail.lane.80 ], !dbg !753
tail.lane.80:
  %t292 = getelementptr inbounds i8, ptr %t289, i64 15, !dbg !753
  %t293 = load i8, ptr %t292, align 1, !dbg !753
  %t294 = insertelement <16 x i8> zeroinitializer, i8 %t293, i32 15, !dbg !753
  br label %tail.lane.79, !dbg !753
tail.lane.79:
  %t295 = phi <16 x i8> [ zeroinitializer, %simd.no.63 ], [ %t294, %tail.lane.80 ], !dbg !753
  %t296 = getelementptr inbounds i8, ptr %t289, i64 14, !dbg !753
  %t297 = load i8, ptr %t296, align 1, !dbg !753
  %t298 = insertelement <16 x i8> %t295, i8 %t297, i32 14, !dbg !753
  br label %tail.lane.78, !dbg !753
tail.lane.78:
  %t299 = phi <16 x i8> [ zeroinitializer, %simd.no.63 ], [ %t298, %tail.lane.79 ], !dbg !753
  %t300 = getelementptr inbounds i8, ptr %t289, i64 13, !dbg !753
  %t301 = load i8, ptr %t300, align 1, !dbg !753
  %t302 = insertelement <16 x i8> %t299, i8 %t301, i32 13, !dbg !753
  br label %tail.lane.77, !dbg !753
tail.lane.77:
  %t303 = phi <16 x i8> [ zeroinitializer, %simd.no.63 ], [ %t302, %tail.lane.78 ], !dbg !753
  %t304 = getelementptr inbounds i8, ptr %t289, i64 12, !dbg !753
  %t305 = load i8, ptr %t304, align 1, !dbg !753
  %t306 = insertelement <16 x i8> %t303, i8 %t305, i32 12, !dbg !753
  br label %tail.lane.76, !dbg !753
tail.lane.76:
  %t307 = phi <16 x i8> [ zeroinitializer, %simd.no.63 ], [ %t306, %tail.lane.77 ], !dbg !753
  %t308 = getelementptr inbounds i8, ptr %t289, i64 11, !dbg !753
  %t309 = load i8, ptr %t308, align 1, !dbg !753
  %t310 = insertelement <16 x i8> %t307, i8 %t309, i32 11, !dbg !753
  br label %tail.lane.75, !dbg !753
tail.lane.75:
  %t311 = phi <16 x i8> [ zeroinitializer, %simd.no.63 ], [ %t310, %tail.lane.76 ], !dbg !753
  %t312 = getelementptr inbounds i8, ptr %t289, i64 10, !dbg !753
  %t313 = load i8, ptr %t312, align 1, !dbg !753
  %t314 = insertelement <16 x i8> %t311, i8 %t313, i32 10, !dbg !753
  br label %tail.lane.74, !dbg !753
tail.lane.74:
  %t315 = phi <16 x i8> [ zeroinitializer, %simd.no.63 ], [ %t314, %tail.lane.75 ], !dbg !753
  %t316 = getelementptr inbounds i8, ptr %t289, i64 9, !dbg !753
  %t317 = load i8, ptr %t316, align 1, !dbg !753
  %t318 = insertelement <16 x i8> %t315, i8 %t317, i32 9, !dbg !753
  br label %tail.lane.73, !dbg !753
tail.lane.73:
  %t319 = phi <16 x i8> [ zeroinitializer, %simd.no.63 ], [ %t318, %tail.lane.74 ], !dbg !753
  %t320 = getelementptr inbounds i8, ptr %t289, i64 8, !dbg !753
  %t321 = load i8, ptr %t320, align 1, !dbg !753
  %t322 = insertelement <16 x i8> %t319, i8 %t321, i32 8, !dbg !753
  br label %tail.lane.72, !dbg !753
tail.lane.72:
  %t323 = phi <16 x i8> [ zeroinitializer, %simd.no.63 ], [ %t322, %tail.lane.73 ], !dbg !753
  %t324 = getelementptr inbounds i8, ptr %t289, i64 7, !dbg !753
  %t325 = load i8, ptr %t324, align 1, !dbg !753
  %t326 = insertelement <16 x i8> %t323, i8 %t325, i32 7, !dbg !753
  br label %tail.lane.71, !dbg !753
tail.lane.71:
  %t327 = phi <16 x i8> [ zeroinitializer, %simd.no.63 ], [ %t326, %tail.lane.72 ], !dbg !753
  %t328 = getelementptr inbounds i8, ptr %t289, i64 6, !dbg !753
  %t329 = load i8, ptr %t328, align 1, !dbg !753
  %t330 = insertelement <16 x i8> %t327, i8 %t329, i32 6, !dbg !753
  br label %tail.lane.70, !dbg !753
tail.lane.70:
  %t331 = phi <16 x i8> [ zeroinitializer, %simd.no.63 ], [ %t330, %tail.lane.71 ], !dbg !753
  %t332 = getelementptr inbounds i8, ptr %t289, i64 5, !dbg !753
  %t333 = load i8, ptr %t332, align 1, !dbg !753
  %t334 = insertelement <16 x i8> %t331, i8 %t333, i32 5, !dbg !753
  br label %tail.lane.69, !dbg !753
tail.lane.69:
  %t335 = phi <16 x i8> [ zeroinitializer, %simd.no.63 ], [ %t334, %tail.lane.70 ], !dbg !753
  %t336 = getelementptr inbounds i8, ptr %t289, i64 4, !dbg !753
  %t337 = load i8, ptr %t336, align 1, !dbg !753
  %t338 = insertelement <16 x i8> %t335, i8 %t337, i32 4, !dbg !753
  br label %tail.lane.68, !dbg !753
tail.lane.68:
  %t339 = phi <16 x i8> [ zeroinitializer, %simd.no.63 ], [ %t338, %tail.lane.69 ], !dbg !753
  %t340 = getelementptr inbounds i8, ptr %t289, i64 3, !dbg !753
  %t341 = load i8, ptr %t340, align 1, !dbg !753
  %t342 = insertelement <16 x i8> %t339, i8 %t341, i32 3, !dbg !753
  br label %tail.lane.67, !dbg !753
tail.lane.67:
  %t343 = phi <16 x i8> [ zeroinitializer, %simd.no.63 ], [ %t342, %tail.lane.68 ], !dbg !753
  %t344 = getelementptr inbounds i8, ptr %t289, i64 2, !dbg !753
  %t345 = load i8, ptr %t344, align 1, !dbg !753
  %t346 = insertelement <16 x i8> %t343, i8 %t345, i32 2, !dbg !753
  br label %tail.lane.66, !dbg !753
tail.lane.66:
  %t347 = phi <16 x i8> [ zeroinitializer, %simd.no.63 ], [ %t346, %tail.lane.67 ], !dbg !753
  %t348 = getelementptr inbounds i8, ptr %t289, i64 1, !dbg !753
  %t349 = load i8, ptr %t348, align 1, !dbg !753
  %t350 = insertelement <16 x i8> %t347, i8 %t349, i32 1, !dbg !753
  br label %tail.lane.65, !dbg !753
tail.lane.65:
  %t351 = phi <16 x i8> [ zeroinitializer, %simd.no.63 ], [ %t350, %tail.lane.66 ], !dbg !753
  %t352 = getelementptr inbounds i8, ptr %t289, i64 0, !dbg !753
  %t353 = load i8, ptr %t352, align 1, !dbg !753
  %t354 = insertelement <16 x i8> %t351, i8 %t353, i32 0, !dbg !753
  br label %tail.done.81, !dbg !753
tail.done.81:
  %t355 = phi <16 x i8> [ zeroinitializer, %simd.no.63 ], [ %t354, %tail.lane.65 ], !dbg !753
  br label %simd.join.64, !dbg !753
simd.join.64:
  %t356 = phi <16 x i8> [ %t291, %simd.yes.62 ], [ %t355, %tail.done.81 ], !dbg !753
  store <16 x i8> %t356, ptr %slot357, !dbg !753
  %t358 = load <16 x i8>, ptr %slot357, !dbg !754
  %t359 = load <16 x i8>, ptr %slot168, !dbg !754
  %t360 = shufflevector <16 x i8> %t358, <16 x i8> %t359, <16 x i32> <i32 15, i32 16, i32 17, i32 18, i32 19, i32 20, i32 21, i32 22, i32 23, i32 24, i32 25, i32 26, i32 27, i32 28, i32 29, i32 30>, !dbg !754
  store <16 x i8> %t360, ptr %slot361, !dbg !754
  %t362 = load <16 x i8>, ptr %slot357, !dbg !755
  %t363 = load <16 x i8>, ptr %slot168, !dbg !755
  %t364 = shufflevector <16 x i8> %t362, <16 x i8> %t363, <16 x i32> <i32 14, i32 15, i32 16, i32 17, i32 18, i32 19, i32 20, i32 21, i32 22, i32 23, i32 24, i32 25, i32 26, i32 27, i32 28, i32 29>, !dbg !755
  store <16 x i8> %t364, ptr %slot365, !dbg !755
  %t366 = load <16 x i8>, ptr %slot357, !dbg !756
  %t367 = load <16 x i8>, ptr %slot168, !dbg !756
  %t368 = shufflevector <16 x i8> %t366, <16 x i8> %t367, <16 x i32> <i32 13, i32 14, i32 15, i32 16, i32 17, i32 18, i32 19, i32 20, i32 21, i32 22, i32 23, i32 24, i32 25, i32 26, i32 27, i32 28>, !dbg !756
  store <16 x i8> %t368, ptr %slot369, !dbg !756
  %t370 = call i32 @nupp.wrap.u32(double 0x0000000000000000), !dbg !757
  %t371 = trunc i32 %t370 to i8, !dbg !757
  %t372 = insertelement <16 x i8> poison, i8 %t371, i64 0, !dbg !757
  %t373 = shufflevector <16 x i8> %t372, <16 x i8> poison, <16 x i32> zeroinitializer, !dbg !757
  store <16 x i8> %t373, ptr %slot374, !dbg !757
  %t375 = load <16 x i8>, ptr %slot374, !dbg !758
  %t376 = call <16 x i8> @ks___nupp_const_decode_fused_f007fffb3d50ef9f__5f5f6e757070436f6e73745f6465636f646546757365645f66303037666666623364353065663966_helper_nibble_table(<16 x i8> %t375, i32 2, i32 2, i32 2, i32 2, i32 2, i32 2, i32 2, i32 2, i32 128, i32 128, i32 128, i32 128, i32 33, i32 1, i32 21, i32 73), !dbg !758
  store <16 x i8> %t376, ptr %slot377, !dbg !758
  %t378 = load <16 x i8>, ptr %slot374, !dbg !759
  %t379 = call <16 x i8> @ks___nupp_const_decode_fused_f007fffb3d50ef9f__5f5f6e757070436f6e73745f6465636f646546757365645f66303037666666623364353065663966_helper_nibble_table(<16 x i8> %t378, i32 231, i32 163, i32 131, i32 131, i32 139, i32 203, i32 203, i32 203, i32 203, i32 203, i32 203, i32 203, i32 203, i32 219, i32 203, i32 203), !dbg !759
  store <16 x i8> %t379, ptr %slot380, !dbg !759
  %t381 = load <16 x i8>, ptr %slot374, !dbg !760
  %t382 = call <16 x i8> @ks___nupp_const_decode_fused_f007fffb3d50ef9f__5f5f6e757070436f6e73745f6465636f646546757365645f66303037666666623364353065663966_helper_nibble_table(<16 x i8> %t381, i32 1, i32 1, i32 1, i32 1, i32 1, i32 1, i32 1, i32 1, i32 230, i32 174, i32 186, i32 186, i32 1, i32 1, i32 1, i32 1), !dbg !760
  store <16 x i8> %t382, ptr %slot383, !dbg !760
  %t384 = load <16 x i8>, ptr %slot377, !dbg !761
  %t385 = load <16 x i8>, ptr %slot361, !dbg !761
  %t386 = call i32 @nupp.wrap.u32(double 0x4010000000000000), !dbg !761
  %t387 = trunc i32 %t386 to i8, !dbg !761
  %t388 = insertelement <16 x i8> poison, i8 %t387, i64 0, !dbg !761
  %t389 = shufflevector <16 x i8> %t388, <16 x i8> poison, <16 x i32> zeroinitializer, !dbg !761
  %t390 = and <16 x i8> %t389, splat (i8 7), !dbg !761
  %t391 = lshr <16 x i8> %t385, %t390, !dbg !761
  %t392 = call i32 @nupp.wrap.u32(double 0x3FF0000000000000), !dbg !761
  %t393 = trunc i32 %t392 to i8, !dbg !761
  %t394 = insertelement <16 x i8> poison, i8 %t393, i64 0, !dbg !761
  %t395 = shufflevector <16 x i8> %t394, <16 x i8> poison, <16 x i32> zeroinitializer, !dbg !761
  %t396 = add <16 x i8> %t391, %t395, !dbg !761
  %t397 = sub <16 x i8> %t396, splat (i8 1), !dbg !761
  %t398 = call <16 x i8> @llvm.aarch64.neon.tbl1.v16i8(<16 x i8> %t384, <16 x i8> %t397), !dbg !761
  %t399 = load <16 x i8>, ptr %slot380, !dbg !761
  %t400 = load <16 x i8>, ptr %slot361, !dbg !761
  %t401 = call i32 @nupp.wrap.u32(double 0x402E000000000000), !dbg !761
  %t402 = trunc i32 %t401 to i8, !dbg !761
  %t403 = insertelement <16 x i8> poison, i8 %t402, i64 0, !dbg !761
  %t404 = shufflevector <16 x i8> %t403, <16 x i8> poison, <16 x i32> zeroinitializer, !dbg !761
  %t405 = and <16 x i8> %t400, %t404, !dbg !761
  %t406 = call i32 @nupp.wrap.u32(double 0x3FF0000000000000), !dbg !761
  %t407 = trunc i32 %t406 to i8, !dbg !761
  %t408 = insertelement <16 x i8> poison, i8 %t407, i64 0, !dbg !761
  %t409 = shufflevector <16 x i8> %t408, <16 x i8> poison, <16 x i32> zeroinitializer, !dbg !761
  %t410 = add <16 x i8> %t405, %t409, !dbg !761
  %t411 = sub <16 x i8> %t410, splat (i8 1), !dbg !761
  %t412 = call <16 x i8> @llvm.aarch64.neon.tbl1.v16i8(<16 x i8> %t399, <16 x i8> %t411), !dbg !761
  %t413 = and <16 x i8> %t398, %t412, !dbg !761
  %t414 = load <16 x i8>, ptr %slot383, !dbg !761
  %t415 = load <16 x i8>, ptr %slot168, !dbg !761
  %t416 = call i32 @nupp.wrap.u32(double 0x4010000000000000), !dbg !761
  %t417 = trunc i32 %t416 to i8, !dbg !761
  %t418 = insertelement <16 x i8> poison, i8 %t417, i64 0, !dbg !761
  %t419 = shufflevector <16 x i8> %t418, <16 x i8> poison, <16 x i32> zeroinitializer, !dbg !761
  %t420 = and <16 x i8> %t419, splat (i8 7), !dbg !761
  %t421 = lshr <16 x i8> %t415, %t420, !dbg !761
  %t422 = call i32 @nupp.wrap.u32(double 0x3FF0000000000000), !dbg !761
  %t423 = trunc i32 %t422 to i8, !dbg !761
  %t424 = insertelement <16 x i8> poison, i8 %t423, i64 0, !dbg !761
  %t425 = shufflevector <16 x i8> %t424, <16 x i8> poison, <16 x i32> zeroinitializer, !dbg !761
  %t426 = add <16 x i8> %t421, %t425, !dbg !761
  %t427 = sub <16 x i8> %t426, splat (i8 1), !dbg !761
  %t428 = call <16 x i8> @llvm.aarch64.neon.tbl1.v16i8(<16 x i8> %t414, <16 x i8> %t427), !dbg !761
  %t429 = and <16 x i8> %t413, %t428, !dbg !761
  store <16 x i8> %t429, ptr %slot430, !dbg !761
  %t431 = call i32 @nupp.wrap.u32(double 0x4060000000000000), !dbg !762
  %t432 = trunc i32 %t431 to i8, !dbg !762
  %t433 = insertelement <16 x i8> poison, i8 %t432, i64 0, !dbg !762
  %t434 = shufflevector <16 x i8> %t433, <16 x i8> poison, <16 x i32> zeroinitializer, !dbg !762
  %t435 = call i32 @nupp.wrap.u32(double 0x0000000000000000), !dbg !762
  %t436 = trunc i32 %t435 to i8, !dbg !762
  %t437 = insertelement <16 x i8> poison, i8 %t436, i64 0, !dbg !762
  %t438 = shufflevector <16 x i8> %t437, <16 x i8> poison, <16 x i32> zeroinitializer, !dbg !762
  %t439 = load <16 x i8>, ptr %slot365, !dbg !762
  %t440 = call i32 @nupp.wrap.u32(double 0x406C000000000000), !dbg !762
  %t441 = trunc i32 %t440 to i8, !dbg !762
  %t442 = insertelement <16 x i8> poison, i8 %t441, i64 0, !dbg !762
  %t443 = shufflevector <16 x i8> %t442, <16 x i8> poison, <16 x i32> zeroinitializer, !dbg !762
  %t444 = icmp uge <16 x i8> %t439, %t443, !dbg !762
  %t445 = load <16 x i8>, ptr %slot369, !dbg !762
  %t446 = call i32 @nupp.wrap.u32(double 0x406E000000000000), !dbg !762
  %t447 = trunc i32 %t446 to i8, !dbg !762
  %t448 = insertelement <16 x i8> poison, i8 %t447, i64 0, !dbg !762
  %t449 = shufflevector <16 x i8> %t448, <16 x i8> poison, <16 x i32> zeroinitializer, !dbg !762
  %t450 = icmp uge <16 x i8> %t445, %t449, !dbg !762
  %t451 = or <16 x i1> %t444, %t450, !dbg !762
  %t452 = select <16 x i1> %t451, <16 x i8> %t434, <16 x i8> %t438, !dbg !762
  store <16 x i8> %t452, ptr %slot453, !dbg !762
  %t454 = load <16 x i8>, ptr %slot430, !dbg !763
  %t455 = load <16 x i8>, ptr %slot453, !dbg !763
  %t456 = xor <16 x i8> %t454, %t455, !dbg !763
  %t457 = call i32 @nupp.wrap.u32(double 0x0000000000000000), !dbg !763
  %t458 = trunc i32 %t457 to i8, !dbg !763
  %t459 = zext i8 %t458 to i32, !dbg !763
  %t460 = call i32 @llvm.aarch64.neon.umaxv.i32.v16i8(<16 x i8> %t456), !dbg !763
  %t461 = trunc i32 %t460 to i8, !dbg !763
  %t462 = zext i8 %t461 to i32, !dbg !763
  %t463 = icmp ne i32 %t462, 0, !dbg !763
  br i1 %t463, label %if.then.83, label %if.else.84, !dbg !763
if.then.83:
  store i1 true, ptr %slot56, !dbg !764
  br label %if.end.82, !dbg !764
if.else.84:
  %t464 = load <16 x i8>, ptr %slot168, !dbg !765
  %t465 = load <16 x i8>, ptr %slot168, !dbg !765
  %t466 = shufflevector <16 x i8> %t464, <16 x i8> %t465, <16 x i32> <i32 15, i32 16, i32 17, i32 18, i32 19, i32 20, i32 21, i32 22, i32 23, i32 24, i32 25, i32 26, i32 27, i32 28, i32 29, i32 30>, !dbg !765
  %t467 = extractelement <16 x i8> %t466, i32 0, !dbg !765
  %t468 = zext i8 %t467 to i32, !dbg !765
  %t469 = icmp uge i32 %t468, 128, !dbg !765
  store i1 %t469, ptr %slot50, !dbg !765
  br label %if.end.82, !dbg !765
if.end.82:
  br label %if.end.59, !dbg !765
if.else.61:
  store i1 false, ptr %slot50, !dbg !766
  br label %if.end.59, !dbg !766
if.end.59:
  %t470 = load i1, ptr %slot56, !dbg !767
  %t471 = xor i1 %t470, true, !dbg !767
  br i1 %t471, label %if.then.86, label %if.else.87, !dbg !767
if.then.86:
  store i32 16, ptr %slot70, !dbg !768
  br label %if.end.85, !dbg !768
if.else.87:
  %t472 = call i64 @llvm.fptosi.sat.i64.f64(double 0x0000000000000000), !dbg !769
  %t473 = call i64 @llvm.fptoui.sat.i64.f64(double 0x0000000000000000), !dbg !769
  %t474 = fcmp olt double 0x0000000000000000, 0.0, !dbg !769
  %t475 = select i1 %t474, i64 %t472, i64 %t473, !dbg !769
  store i64 %t475, ptr %slot68, !dbg !769
  br label %if.end.85, !dbg !769
if.end.85:
  br label %if.end.22, !dbg !769
if.else.26:
  br label %if.end.22, !dbg !769
if.end.22:
  br label %if.end.19, !dbg !769
if.else.21:
  br label %if.end.19, !dbg !769
if.end.19:
  %t476 = load i32, ptr %slot70, !dbg !770
  %t477 = icmp eq i32 %t476, 0, !dbg !770
  br i1 %t477, label %and.rhs.89, label %and.end.90, !dbg !770
and.rhs.89:
  %t478 = load i1, ptr %slot49, !dbg !770
  %t479 = xor i1 %t478, true, !dbg !770
  br label %and.end.90, !dbg !770
and.end.90:
  %t480 = phi i1 [ false, %if.end.19 ], [ %t479, %and.rhs.89 ], !dbg !770
  br i1 %t480, label %if.then.91, label %if.else.92, !dbg !770
if.then.91:
  store i1 true, ptr %slot49, !dbg !771
  %t481 = call i32 @nupp.wrap.u32(double 0x3FF0000000000000), !dbg !772
  store i32 %t481, ptr %slot482, !dbg !772
  store i1 true, ptr %slot483, !dbg !773
  br label %while.head.93, !dbg !774
while.head.93:
  %t484 = load i1, ptr %slot483, !dbg !774
  br i1 %t484, label %and.rhs.96, label %and.end.97, !dbg !774
and.rhs.96:
  %t485 = load i32, ptr %slot482, !dbg !774
  %t486 = icmp ule i32 %t485, 3, !dbg !774
  br label %and.end.97, !dbg !774
and.end.97:
  %t487 = phi i1 [ false, %while.head.93 ], [ %t486, %and.rhs.96 ], !dbg !774
  br i1 %t487, label %and.rhs.98, label %and.end.99, !dbg !774
and.rhs.98:
  %t488 = load i32, ptr %slot482, !dbg !774
  %t489 = load i32, ptr %slot33, !dbg !774
  %t490 = icmp ule i32 %t488, %t489, !dbg !774
  br label %and.end.99, !dbg !774
and.end.99:
  %t491 = phi i1 [ false, %and.end.97 ], [ %t490, %and.rhs.98 ], !dbg !774
  br i1 %t491, label %while.body.94, label %while.end.95, !dbg !774
while.body.94:
  %t492 = load i32, ptr %slot33, !dbg !775
  %t493 = load i32, ptr %slot482, !dbg !775
  %t494 = sub i32 %t492, %t493, !dbg !775
  %t495 = zext i32 %t494 to i64, !dbg !775
  %t496 = icmp uge i64 %t495, %t15, !dbg !775
  br i1 %t496, label %lua.raise.100, label %lua.ok.101, !prof !7, !dbg !775
lua.raise.100:
  %t497 = getelementptr inbounds ptr, ptr %t1, i64 11, !dbg !775
  %rt.raise.498 = load ptr, ptr %t497, !invariant.load !8, !dbg !775
  call void %rt.raise.498(ptr %L, i64 3) nomerge, !dbg !775
  unreachable, !dbg !775
lua.ok.101:
  %t499 = getelementptr inbounds i8, ptr %t14, i64 %t495, !dbg !775
  %t500 = load i8, ptr %t499, !dbg !775
  %t501 = zext i8 %t500 to i32, !dbg !775
  store i32 %t501, ptr %slot502, !dbg !775
  %t503 = load i32, ptr %slot502, !dbg !776
  %t504 = icmp ult i32 %t503, 128, !dbg !776
  br i1 %t504, label %if.then.103, label %if.else.104, !dbg !776
if.then.103:
  store i1 false, ptr %slot483, !dbg !777
  br label %if.end.102, !dbg !777
if.else.104:
  %t505 = load i32, ptr %slot502, !dbg !777
  %t506 = icmp uge i32 %t505, 192, !dbg !777
  br i1 %t506, label %if.then.105, label %if.else.106, !dbg !777
if.then.105:
  %t507 = load i32, ptr %slot502, !dbg !778
  %t508 = icmp ult i32 %t507, 194, !dbg !778
  br i1 %t508, label %or.end.109, label %or.rhs.108, !dbg !778
or.rhs.108:
  %t509 = load i32, ptr %slot502, !dbg !778
  %t510 = icmp ugt i32 %t509, 244, !dbg !778
  br label %or.end.109, !dbg !778
or.end.109:
  %t511 = phi i1 [ true, %if.then.105 ], [ %t510, %or.rhs.108 ], !dbg !778
  br i1 %t511, label %if.then.110, label %if.else.111, !dbg !778
if.then.110:
  call void @lua_pushvalue(ptr %L, i32 2), !dbg !779
  %t512 = call i32 @nupp.wrap.u32(double 0x4000000000000000), !dbg !779
  %t513 = uitofp i32 %t512 to double, !dbg !779
  call void @lua_pushnumber(ptr %L, double %t513), !dbg !779
  %t514 = load i32, ptr %slot33, !dbg !779
  %t515 = load i32, ptr %slot482, !dbg !779
  %t516 = sub i32 %t514, %t515, !dbg !779
  %t517 = add i32 %t516, 1, !dbg !779
  %t518 = uitofp i32 %t517 to double, !dbg !779
  call void @lua_pushnumber(ptr %L, double %t518), !dbg !779
  ret i32 3, !dbg !779
if.else.111:
  br label %if.end.107, !dbg !779
if.end.107:
  %t519 = call i32 @nupp.wrap.u32(double 0x4008000000000000), !dbg !780
  store i32 %t519, ptr %slot520, !dbg !780
  %t521 = load i32, ptr %slot502, !dbg !781
  %t522 = icmp ule i32 %t521, 223, !dbg !781
  br i1 %t522, label %if.then.113, label %if.else.114, !dbg !781
if.then.113:
  %t523 = call i32 @nupp.wrap.u32(double 0x3FF0000000000000), !dbg !782
  store i32 %t523, ptr %slot520, !dbg !782
  br label %if.end.112, !dbg !782
if.else.114:
  %t524 = load i32, ptr %slot502, !dbg !782
  %t525 = icmp ule i32 %t524, 239, !dbg !782
  br i1 %t525, label %if.then.115, label %if.else.116, !dbg !782
if.then.115:
  %t526 = call i32 @nupp.wrap.u32(double 0x4000000000000000), !dbg !783
  store i32 %t526, ptr %slot520, !dbg !783
  br label %if.end.112, !dbg !783
if.else.116:
  br label %if.end.112, !dbg !783
if.end.112:
  %t527 = load i32, ptr %slot520, !dbg !784
  %t528 = load i32, ptr %slot482, !dbg !784
  %t529 = icmp uge i32 %t527, %t528, !dbg !784
  br i1 %t529, label %if.then.118, label %if.else.119, !dbg !784
if.then.118:
  %t530 = load i32, ptr %slot520, !dbg !785
  %t531 = load i32, ptr %slot482, !dbg !785
  %t532 = sub i32 %t530, %t531, !dbg !785
  %t533 = add i32 %t532, 1, !dbg !785
  store i32 %t533, ptr %slot43, !dbg !785
  store i1 true, ptr %slot46, !dbg !786
  %t534 = load i32, ptr %slot33, !dbg !787
  %t535 = sub i32 %t534, 1, !dbg !787
  store i32 %t535, ptr %slot48, !dbg !787
  %t536 = load i32, ptr %slot482, !dbg !788
  %t537 = icmp eq i32 %t536, 1, !dbg !788
  br i1 %t537, label %if.then.121, label %if.else.122, !dbg !788
if.then.121:
  %t538 = load i32, ptr %slot502, !dbg !789
  %t539 = icmp eq i32 %t538, 224, !dbg !789
  br i1 %t539, label %if.then.124, label %if.else.125, !dbg !789
if.then.124:
  %t540 = call i32 @nupp.wrap.u32(double 0x3FF0000000000000), !dbg !790
  store i32 %t540, ptr %slot45, !dbg !790
  br label %if.end.123, !dbg !790
if.else.125:
  %t541 = load i32, ptr %slot502, !dbg !790
  %t542 = icmp eq i32 %t541, 237, !dbg !790
  br i1 %t542, label %if.then.126, label %if.else.127, !dbg !790
if.then.126:
  %t543 = call i32 @nupp.wrap.u32(double 0x4000000000000000), !dbg !791
  store i32 %t543, ptr %slot45, !dbg !791
  br label %if.end.123, !dbg !791
if.else.127:
  %t544 = load i32, ptr %slot502, !dbg !791
  %t545 = icmp eq i32 %t544, 240, !dbg !791
  br i1 %t545, label %if.then.128, label %if.else.129, !dbg !791
if.then.128:
  %t546 = call i32 @nupp.wrap.u32(double 0x4008000000000000), !dbg !792
  store i32 %t546, ptr %slot45, !dbg !792
  br label %if.end.123, !dbg !792
if.else.129:
  %t547 = load i32, ptr %slot502, !dbg !792
  %t548 = icmp eq i32 %t547, 244, !dbg !792
  br i1 %t548, label %if.then.130, label %if.else.131, !dbg !792
if.then.130:
  %t549 = call i32 @nupp.wrap.u32(double 0x4010000000000000), !dbg !793
  store i32 %t549, ptr %slot45, !dbg !793
  br label %if.end.123, !dbg !793
if.else.131:
  br label %if.end.123, !dbg !793
if.end.123:
  br label %if.end.120, !dbg !793
if.else.122:
  br label %if.end.120, !dbg !793
if.end.120:
  br label %if.end.117, !dbg !793
if.else.119:
  br label %if.end.117, !dbg !793
if.end.117:
  store i1 false, ptr %slot483, !dbg !794
  br label %if.end.102, !dbg !794
if.else.106:
  %t550 = load i32, ptr %slot482, !dbg !795
  %t551 = add i32 %t550, 1, !dbg !795
  store i32 %t551, ptr %slot482, !dbg !795
  br label %if.end.102, !dbg !795
if.end.102:
  br label %while.head.93, !dbg !795
while.end.95:
  br label %if.end.88, !dbg !795
if.else.92:
  %t552 = load i32, ptr %slot70, !dbg !795
  %t553 = icmp eq i32 %t552, 0, !dbg !795
  br i1 %t553, label %if.then.132, label %if.else.133, !dbg !795
if.then.132:
  %t554 = load i32, ptr %slot33, !dbg !796
  %t555 = load i32, ptr %slot20, !dbg !796
  %t556 = icmp ult i32 %t554, %t555, !dbg !796
  br i1 %t556, label %if.then.135, label %if.else.136, !dbg !796
if.then.135:
  %t557 = load i32, ptr %slot33, !dbg !797
  %t558 = zext i32 %t557 to i64, !dbg !797
  %t559 = getelementptr inbounds i8, ptr %t14, i64 %t558, !dbg !797
  %t560 = load i8, ptr %t559, !dbg !797
  %t561 = zext i8 %t560 to i32, !dbg !797
  store i32 %t561, ptr %slot562, !dbg !797
  %t563 = load i32, ptr %slot562, !dbg !798
  %t564 = icmp eq i32 %t563, 34, !dbg !798
  br i1 %t564, label %or.end.139, label %or.rhs.138, !dbg !798
or.rhs.138:
  %t565 = load i32, ptr %slot562, !dbg !798
  %t566 = icmp eq i32 %t565, 92, !dbg !798
  br label %or.end.139, !dbg !798
or.end.139:
  %t567 = phi i1 [ true, %if.then.135 ], [ %t566, %or.rhs.138 ], !dbg !798
  br i1 %t567, label %or.end.141, label %or.rhs.140, !dbg !798
or.rhs.140:
  %t568 = load i32, ptr %slot562, !dbg !798
  %t569 = icmp ult i32 %t568, 32, !dbg !798
  br label %or.end.141, !dbg !798
or.end.141:
  %t570 = phi i1 [ true, %or.end.139 ], [ %t569, %or.rhs.140 ], !dbg !798
  br i1 %t570, label %or.end.143, label %or.rhs.142, !dbg !798
or.rhs.142:
  %t571 = load i32, ptr %slot562, !dbg !798
  %t572 = icmp eq i32 %t571, 123, !dbg !798
  br label %or.end.143, !dbg !798
or.end.143:
  %t573 = phi i1 [ true, %or.end.141 ], [ %t572, %or.rhs.142 ], !dbg !798
  br i1 %t573, label %or.end.145, label %or.rhs.144, !dbg !798
or.rhs.144:
  %t574 = load i32, ptr %slot562, !dbg !798
  %t575 = icmp eq i32 %t574, 125, !dbg !798
  br label %or.end.145, !dbg !798
or.end.145:
  %t576 = phi i1 [ true, %or.end.143 ], [ %t575, %or.rhs.144 ], !dbg !798
  br i1 %t576, label %or.end.147, label %or.rhs.146, !dbg !798
or.rhs.146:
  %t577 = load i32, ptr %slot562, !dbg !798
  %t578 = icmp eq i32 %t577, 91, !dbg !798
  br label %or.end.147, !dbg !798
or.end.147:
  %t579 = phi i1 [ true, %or.end.145 ], [ %t578, %or.rhs.146 ], !dbg !798
  br i1 %t579, label %or.end.149, label %or.rhs.148, !dbg !798
or.rhs.148:
  %t580 = load i32, ptr %slot562, !dbg !798
  %t581 = icmp eq i32 %t580, 93, !dbg !798
  br label %or.end.149, !dbg !798
or.end.149:
  %t582 = phi i1 [ true, %or.end.147 ], [ %t581, %or.rhs.148 ], !dbg !798
  br i1 %t582, label %or.end.151, label %or.rhs.150, !dbg !798
or.rhs.150:
  %t583 = load i32, ptr %slot562, !dbg !798
  %t584 = icmp eq i32 %t583, 58, !dbg !798
  br label %or.end.151, !dbg !798
or.end.151:
  %t585 = phi i1 [ true, %or.end.149 ], [ %t584, %or.rhs.150 ], !dbg !798
  br i1 %t585, label %or.end.153, label %or.rhs.152, !dbg !798
or.rhs.152:
  %t586 = load i32, ptr %slot562, !dbg !798
  %t587 = icmp eq i32 %t586, 44, !dbg !798
  br label %or.end.153, !dbg !798
or.end.153:
  %t588 = phi i1 [ true, %or.end.151 ], [ %t587, %or.rhs.152 ], !dbg !798
  br i1 %t588, label %or.end.155, label %or.rhs.154, !dbg !798
or.rhs.154:
  %t589 = load i32, ptr %slot562, !dbg !798
  %t590 = icmp uge i32 %t589, 128, !dbg !798
  br label %or.end.155, !dbg !798
or.end.155:
  %t591 = phi i1 [ true, %or.end.153 ], [ %t590, %or.rhs.154 ], !dbg !798
  br i1 %t591, label %if.then.156, label %if.else.157, !dbg !798
if.then.156:
  %t592 = load i64, ptr %slot55, !dbg !799
  store i64 %t592, ptr %slot68, !dbg !799
  br label %if.end.137, !dbg !799
if.else.157:
  br label %if.end.137, !dbg !799
if.end.137:
  br label %if.end.134, !dbg !799
if.else.136:
  br label %if.end.134, !dbg !799
if.end.134:
  %t593 = call i32 @nupp.wrap.u32(double 0x3FF0000000000000), !dbg !800
  store i32 %t593, ptr %slot70, !dbg !800
  br label %if.end.88, !dbg !800
if.else.133:
  br label %if.end.88, !dbg !800
if.end.88:
  br label %while.head.158, !dbg !801
while.head.158:
  %t594 = load i64, ptr %slot68, !dbg !801
  %t595 = call i64 @llvm.fptosi.sat.i64.f64(double 0x0000000000000000), !dbg !801
  %t596 = call i64 @llvm.fptoui.sat.i64.f64(double 0x0000000000000000), !dbg !801
  %t597 = fcmp olt double 0x0000000000000000, 0.0, !dbg !801
  %t598 = select i1 %t597, i64 %t595, i64 %t596, !dbg !801
  %t599 = icmp ne i64 %t594, %t598, !dbg !801
  br i1 %t599, label %while.body.159, label %while.end.160, !dbg !801
while.body.159:
  %t600 = load i64, ptr %slot68, !dbg !802
  %t601 = call i64 @llvm.cttz.i64(i64 %t600, i1 false), !dbg !802
  %t602 = trunc i64 %t601 to i32, !dbg !802
  store i32 %t602, ptr %slot603, !dbg !802
  %t604 = load i64, ptr %slot68, !dbg !803
  %t605 = load i64, ptr %slot68, !dbg !803
  %t606 = call i64 @llvm.fptosi.sat.i64.f64(double 0x3FF0000000000000), !dbg !803
  %t607 = call i64 @llvm.fptoui.sat.i64.f64(double 0x3FF0000000000000), !dbg !803
  %t608 = fcmp olt double 0x3FF0000000000000, 0.0, !dbg !803
  %t609 = select i1 %t608, i64 %t606, i64 %t607, !dbg !803
  %t610 = sub i64 %t605, %t609, !dbg !803
  %t611 = and i64 %t604, %t610, !dbg !803
  store i64 %t611, ptr %slot68, !dbg !803
  %t612 = load i32, ptr %slot33, !dbg !804
  %t613 = load i32, ptr %slot603, !dbg !804
  %t614 = add i32 %t612, %t613, !dbg !804
  store i32 %t614, ptr %slot615, !dbg !804
  %t616 = load i32, ptr %slot615, !dbg !805
  %t617 = load i32, ptr %slot20, !dbg !805
  %t618 = icmp ult i32 %t616, %t617, !dbg !805
  br i1 %t618, label %if.then.162, label %if.else.163, !dbg !805
if.then.162:
  %t619 = load i32, ptr %slot615, !dbg !806
  %t620 = zext i32 %t619 to i64, !dbg !806
  %t621 = getelementptr inbounds i8, ptr %t14, i64 %t620, !dbg !806
  %t622 = load i8, ptr %t621, !dbg !806
  %t623 = zext i8 %t622 to i32, !dbg !806
  store i32 %t623, ptr %slot624, !dbg !806
  %t625 = load i32, ptr %slot43, !dbg !807
  %t626 = icmp ne i32 %t625, 0, !dbg !807
  br i1 %t626, label %and.rhs.165, label %and.end.166, !dbg !807
and.rhs.165:
  %t627 = load i1, ptr %slot46, !dbg !807
  %t628 = xor i1 %t627, true, !dbg !807
  br i1 %t628, label %or.end.168, label %or.rhs.167, !dbg !807
or.rhs.167:
  %t629 = load i32, ptr %slot615, !dbg !807
  %t630 = load i32, ptr %slot48, !dbg !807
  %t631 = add i32 %t630, 1, !dbg !807
  %t632 = icmp ne i32 %t629, %t631, !dbg !807
  br label %or.end.168, !dbg !807
or.end.168:
  %t633 = phi i1 [ true, %and.rhs.165 ], [ %t632, %or.rhs.167 ], !dbg !807
  br label %and.end.166, !dbg !807
and.end.166:
  %t634 = phi i1 [ false, %if.then.162 ], [ %t633, %or.end.168 ], !dbg !807
  br i1 %t634, label %if.then.169, label %if.else.170, !dbg !807
if.then.169:
  call void @lua_pushvalue(ptr %L, i32 2), !dbg !808
  %t635 = call i32 @nupp.wrap.u32(double 0x4000000000000000), !dbg !808
  %t636 = uitofp i32 %t635 to double, !dbg !808
  call void @lua_pushnumber(ptr %L, double %t636), !dbg !808
  %t637 = load i32, ptr %slot48, !dbg !808
  %t638 = add i32 %t637, 2, !dbg !808
  %t639 = uitofp i32 %t638 to double, !dbg !808
  call void @lua_pushnumber(ptr %L, double %t639), !dbg !808
  ret i32 3, !dbg !808
if.else.170:
  br label %if.end.164, !dbg !808
if.end.164:
  %t640 = load i32, ptr %slot624, !dbg !809
  %t641 = icmp uge i32 %t640, 128, !dbg !809
  br i1 %t641, label %if.then.172, label %if.else.173, !dbg !809
if.then.172:
  %t642 = load i32, ptr %slot624, !dbg !810
  %t643 = icmp ule i32 %t642, 191, !dbg !810
  store i1 %t643, ptr %slot644, !dbg !810
  %t645 = load i32, ptr %slot43, !dbg !811
  %t646 = icmp ne i32 %t645, 0, !dbg !811
  br i1 %t646, label %if.then.175, label %if.else.176, !dbg !811
if.then.175:
  %t647 = load i1, ptr %slot644, !dbg !812
  %t648 = xor i1 %t647, true, !dbg !812
  br i1 %t648, label %if.then.178, label %if.else.179, !dbg !812
if.then.178:
  call void @lua_pushvalue(ptr %L, i32 2), !dbg !813
  %t649 = call i32 @nupp.wrap.u32(double 0x4000000000000000), !dbg !813
  %t650 = uitofp i32 %t649 to double, !dbg !813
  call void @lua_pushnumber(ptr %L, double %t650), !dbg !813
  %t651 = load i32, ptr %slot615, !dbg !813
  %t652 = add i32 %t651, 1, !dbg !813
  %t653 = uitofp i32 %t652 to double, !dbg !813
  call void @lua_pushnumber(ptr %L, double %t653), !dbg !813
  ret i32 3, !dbg !813
if.else.179:
  br label %if.end.177, !dbg !813
if.end.177:
  %t654 = load i32, ptr %slot45, !dbg !814
  %t655 = icmp eq i32 %t654, 1, !dbg !814
  br i1 %t655, label %and.rhs.180, label %and.end.181, !dbg !814
and.rhs.180:
  %t656 = load i32, ptr %slot624, !dbg !814
  %t657 = icmp ult i32 %t656, 160, !dbg !814
  br label %and.end.181, !dbg !814
and.end.181:
  %t658 = phi i1 [ false, %if.end.177 ], [ %t657, %and.rhs.180 ], !dbg !814
  br i1 %t658, label %or.end.183, label %or.rhs.182, !dbg !814
or.rhs.182:
  %t659 = load i32, ptr %slot45, !dbg !814
  %t660 = icmp eq i32 %t659, 2, !dbg !814
  br i1 %t660, label %and.rhs.184, label %and.end.185, !dbg !814
and.rhs.184:
  %t661 = load i32, ptr %slot624, !dbg !814
  %t662 = icmp ugt i32 %t661, 159, !dbg !814
  br label %and.end.185, !dbg !814
and.end.185:
  %t663 = phi i1 [ false, %or.rhs.182 ], [ %t662, %and.rhs.184 ], !dbg !814
  br label %or.end.183, !dbg !814
or.end.183:
  %t664 = phi i1 [ true, %and.end.181 ], [ %t663, %and.end.185 ], !dbg !814
  br i1 %t664, label %or.end.187, label %or.rhs.186, !dbg !814
or.rhs.186:
  %t665 = load i32, ptr %slot45, !dbg !814
  %t666 = icmp eq i32 %t665, 3, !dbg !814
  br i1 %t666, label %and.rhs.188, label %and.end.189, !dbg !814
and.rhs.188:
  %t667 = load i32, ptr %slot624, !dbg !814
  %t668 = icmp ult i32 %t667, 144, !dbg !814
  br label %and.end.189, !dbg !814
and.end.189:
  %t669 = phi i1 [ false, %or.rhs.186 ], [ %t668, %and.rhs.188 ], !dbg !814
  br label %or.end.187, !dbg !814
or.end.187:
  %t670 = phi i1 [ true, %or.end.183 ], [ %t669, %and.end.189 ], !dbg !814
  br i1 %t670, label %or.end.191, label %or.rhs.190, !dbg !814
or.rhs.190:
  %t671 = load i32, ptr %slot45, !dbg !814
  %t672 = icmp eq i32 %t671, 4, !dbg !814
  br i1 %t672, label %and.rhs.192, label %and.end.193, !dbg !814
and.rhs.192:
  %t673 = load i32, ptr %slot624, !dbg !814
  %t674 = icmp ugt i32 %t673, 143, !dbg !814
  br label %and.end.193, !dbg !814
and.end.193:
  %t675 = phi i1 [ false, %or.rhs.190 ], [ %t674, %and.rhs.192 ], !dbg !814
  br label %or.end.191, !dbg !814
or.end.191:
  %t676 = phi i1 [ true, %or.end.187 ], [ %t675, %and.end.193 ], !dbg !814
  store i1 %t676, ptr %slot677, !dbg !814
  %t678 = load i1, ptr %slot677, !dbg !815
  br i1 %t678, label %if.then.195, label %if.else.196, !dbg !815
if.then.195:
  call void @lua_pushvalue(ptr %L, i32 2), !dbg !816
  %t679 = call i32 @nupp.wrap.u32(double 0x4000000000000000), !dbg !816
  %t680 = uitofp i32 %t679 to double, !dbg !816
  call void @lua_pushnumber(ptr %L, double %t680), !dbg !816
  %t681 = load i32, ptr %slot615, !dbg !816
  %t682 = add i32 %t681, 1, !dbg !816
  %t683 = uitofp i32 %t682 to double, !dbg !816
  call void @lua_pushnumber(ptr %L, double %t683), !dbg !816
  ret i32 3, !dbg !816
if.else.196:
  br label %if.end.194, !dbg !816
if.end.194:
  %t684 = load i32, ptr %slot43, !dbg !817
  %t685 = sub i32 %t684, 1, !dbg !817
  store i32 %t685, ptr %slot43, !dbg !817
  %t686 = call i32 @nupp.wrap.u32(double 0x0000000000000000), !dbg !818
  store i32 %t686, ptr %slot45, !dbg !818
  br label %if.end.174, !dbg !818
if.else.176:
  %t687 = load i1, ptr %slot644, !dbg !818
  br i1 %t687, label %or.end.198, label %or.rhs.197, !dbg !818
or.rhs.197:
  %t688 = load i32, ptr %slot624, !dbg !818
  %t689 = icmp ult i32 %t688, 194, !dbg !818
  br label %or.end.198, !dbg !818
or.end.198:
  %t690 = phi i1 [ true, %if.else.176 ], [ %t689, %or.rhs.197 ], !dbg !818
  br i1 %t690, label %or.end.200, label %or.rhs.199, !dbg !818
or.rhs.199:
  %t691 = load i32, ptr %slot624, !dbg !818
  %t692 = icmp ugt i32 %t691, 244, !dbg !818
  br label %or.end.200, !dbg !818
or.end.200:
  %t693 = phi i1 [ true, %or.end.198 ], [ %t692, %or.rhs.199 ], !dbg !818
  br i1 %t693, label %if.then.201, label %if.else.202, !dbg !818
if.then.201:
  call void @lua_pushvalue(ptr %L, i32 2), !dbg !819
  %t694 = call i32 @nupp.wrap.u32(double 0x4000000000000000), !dbg !819
  %t695 = uitofp i32 %t694 to double, !dbg !819
  call void @lua_pushnumber(ptr %L, double %t695), !dbg !819
  %t696 = load i32, ptr %slot615, !dbg !819
  %t697 = add i32 %t696, 1, !dbg !819
  %t698 = uitofp i32 %t697 to double, !dbg !819
  call void @lua_pushnumber(ptr %L, double %t698), !dbg !819
  ret i32 3, !dbg !819
if.else.202:
  %t699 = load i32, ptr %slot624, !dbg !819
  %t700 = icmp ule i32 %t699, 223, !dbg !819
  br i1 %t700, label %if.then.203, label %if.else.204, !dbg !819
if.then.203:
  %t701 = call i32 @nupp.wrap.u32(double 0x3FF0000000000000), !dbg !820
  store i32 %t701, ptr %slot43, !dbg !820
  br label %if.end.174, !dbg !820
if.else.204:
  %t702 = load i32, ptr %slot624, !dbg !820
  %t703 = icmp ule i32 %t702, 239, !dbg !820
  br i1 %t703, label %if.then.205, label %if.else.206, !dbg !820
if.then.205:
  %t704 = call i32 @nupp.wrap.u32(double 0x4000000000000000), !dbg !821
  store i32 %t704, ptr %slot43, !dbg !821
  %t705 = load i32, ptr %slot624, !dbg !822
  %t706 = icmp eq i32 %t705, 224, !dbg !822
  br i1 %t706, label %if.then.208, label %if.else.209, !dbg !822
if.then.208:
  %t707 = call i32 @nupp.wrap.u32(double 0x3FF0000000000000), !dbg !823
  store i32 %t707, ptr %slot45, !dbg !823
  br label %if.end.207, !dbg !823
if.else.209:
  %t708 = load i32, ptr %slot624, !dbg !823
  %t709 = icmp eq i32 %t708, 237, !dbg !823
  br i1 %t709, label %if.then.210, label %if.else.211, !dbg !823
if.then.210:
  %t710 = call i32 @nupp.wrap.u32(double 0x4000000000000000), !dbg !824
  store i32 %t710, ptr %slot45, !dbg !824
  br label %if.end.207, !dbg !824
if.else.211:
  br label %if.end.207, !dbg !824
if.end.207:
  br label %if.end.174, !dbg !824
if.else.206:
  %t711 = call i32 @nupp.wrap.u32(double 0x4008000000000000), !dbg !825
  store i32 %t711, ptr %slot43, !dbg !825
  %t712 = load i32, ptr %slot624, !dbg !826
  %t713 = icmp eq i32 %t712, 240, !dbg !826
  br i1 %t713, label %if.then.213, label %if.else.214, !dbg !826
if.then.213:
  %t714 = call i32 @nupp.wrap.u32(double 0x4008000000000000), !dbg !827
  store i32 %t714, ptr %slot45, !dbg !827
  br label %if.end.212, !dbg !827
if.else.214:
  %t715 = load i32, ptr %slot624, !dbg !827
  %t716 = icmp eq i32 %t715, 244, !dbg !827
  br i1 %t716, label %if.then.215, label %if.else.216, !dbg !827
if.then.215:
  %t717 = call i32 @nupp.wrap.u32(double 0x4010000000000000), !dbg !828
  store i32 %t717, ptr %slot45, !dbg !828
  br label %if.end.212, !dbg !828
if.else.216:
  br label %if.end.212, !dbg !828
if.end.212:
  br label %if.end.174, !dbg !828
if.end.174:
  store i1 true, ptr %slot46, !dbg !829
  %t718 = load i32, ptr %slot615, !dbg !830
  store i32 %t718, ptr %slot48, !dbg !830
  store i1 false, ptr %slot39, !dbg !831
  store i1 false, ptr %slot38, !dbg !832
  br label %if.end.171, !dbg !832
if.else.173:
  %t719 = load i32, ptr %slot43, !dbg !832
  %t720 = icmp ne i32 %t719, 0, !dbg !832
  br i1 %t720, label %if.then.217, label %if.else.218, !dbg !832
if.then.217:
  call void @lua_pushvalue(ptr %L, i32 2), !dbg !833
  %t721 = call i32 @nupp.wrap.u32(double 0x4000000000000000), !dbg !833
  %t722 = uitofp i32 %t721 to double, !dbg !833
  call void @lua_pushnumber(ptr %L, double %t722), !dbg !833
  %t723 = load i32, ptr %slot615, !dbg !833
  %t724 = add i32 %t723, 1, !dbg !833
  %t725 = uitofp i32 %t724 to double, !dbg !833
  call void @lua_pushnumber(ptr %L, double %t725), !dbg !833
  ret i32 3, !dbg !833
if.else.218:
  %t726 = load i32, ptr %slot624, !dbg !833
  %t727 = icmp eq i32 %t726, 92, !dbg !833
  br i1 %t727, label %if.then.219, label %if.else.220, !dbg !833
if.then.219:
  %t728 = load i1, ptr %slot36, !dbg !834
  %t729 = xor i1 %t728, true, !dbg !834
  br i1 %t729, label %if.then.222, label %if.else.223, !dbg !834
if.then.222:
  call void @lua_pushvalue(ptr %L, i32 2), !dbg !835
  %t730 = call i32 @nupp.wrap.u32(double 0x4010000000000000), !dbg !835
  %t731 = uitofp i32 %t730 to double, !dbg !835
  call void @lua_pushnumber(ptr %L, double %t731), !dbg !835
  %t732 = load i32, ptr %slot615, !dbg !835
  %t733 = add i32 %t732, 1, !dbg !835
  %t734 = uitofp i32 %t733 to double, !dbg !835
  call void @lua_pushnumber(ptr %L, double %t734), !dbg !835
  ret i32 3, !dbg !835
if.else.223:
  br label %if.end.221, !dbg !835
if.end.221:
  %t735 = load i1, ptr %slot39, !dbg !836
  br i1 %t735, label %and.rhs.225, label %and.end.226, !dbg !836
and.rhs.225:
  %t736 = load i32, ptr %slot615, !dbg !836
  %t737 = load i32, ptr %slot41, !dbg !836
  %t738 = add i32 %t737, 1, !dbg !836
  %t739 = icmp eq i32 %t736, %t738, !dbg !836
  br label %and.end.226, !dbg !836
and.end.226:
  %t740 = phi i1 [ false, %if.end.221 ], [ %t739, %and.rhs.225 ], !dbg !836
  br i1 %t740, label %if.then.227, label %if.else.228, !dbg !836
if.then.227:
  %t741 = load i1, ptr %slot38, !dbg !837
  %t742 = xor i1 %t741, true, !dbg !837
  store i1 %t742, ptr %slot38, !dbg !837
  br label %if.end.224, !dbg !837
if.else.228:
  store i1 true, ptr %slot38, !dbg !838
  br label %if.end.224, !dbg !838
if.end.224:
  store i1 true, ptr %slot39, !dbg !839
  %t743 = load i32, ptr %slot615, !dbg !840
  store i32 %t743, ptr %slot41, !dbg !840
  store i1 true, ptr %slot37, !dbg !841
  br label %if.end.171, !dbg !841
if.else.220:
  %t744 = load i1, ptr %slot39, !dbg !842
  br i1 %t744, label %and.rhs.229, label %and.end.230, !dbg !842
and.rhs.229:
  %t745 = load i32, ptr %slot615, !dbg !842
  %t746 = load i32, ptr %slot41, !dbg !842
  %t747 = add i32 %t746, 1, !dbg !842
  %t748 = icmp eq i32 %t745, %t747, !dbg !842
  br label %and.end.230, !dbg !842
and.end.230:
  %t749 = phi i1 [ false, %if.else.220 ], [ %t748, %and.rhs.229 ], !dbg !842
  br i1 %t749, label %and.rhs.231, label %and.end.232, !dbg !842
and.rhs.231:
  %t750 = load i1, ptr %slot38, !dbg !842
  br label %and.end.232, !dbg !842
and.end.232:
  %t751 = phi i1 [ false, %and.end.230 ], [ %t750, %and.rhs.231 ], !dbg !842
  store i1 %t751, ptr %slot752, !dbg !842
  %t753 = load i32, ptr %slot624, !dbg !843
  %t754 = icmp eq i32 %t753, 34, !dbg !843
  br i1 %t754, label %and.rhs.234, label %and.end.235, !dbg !843
and.rhs.234:
  %t755 = load i1, ptr %slot752, !dbg !843
  %t756 = xor i1 %t755, true, !dbg !843
  br label %and.end.235, !dbg !843
and.end.235:
  %t757 = phi i1 [ false, %and.end.232 ], [ %t756, %and.rhs.234 ], !dbg !843
  br i1 %t757, label %if.then.236, label %if.else.237, !dbg !843
if.then.236:
  %t758 = load i1, ptr %slot36, !dbg !844
  br i1 %t758, label %if.then.239, label %if.else.240, !dbg !844
if.then.239:
  %t759 = load i32, ptr %slot615, !dbg !845
  store i32 %t759, ptr %slot760, !dbg !845
  %t761 = load i1, ptr %slot37, !dbg !846
  br i1 %t761, label %if.then.242, label %if.else.243, !dbg !846
if.then.242:
  %t762 = load i32, ptr %slot615, !dbg !847
  %t763 = or i32 %t762, 2147483648, !dbg !847
  store i32 %t763, ptr %slot760, !dbg !847
  br label %if.end.241, !dbg !847
if.else.243:
  br label %if.end.241, !dbg !847
if.end.241:
  %t764 = load i32, ptr %slot35, !dbg !848
  %t765 = load i32, ptr %slot760, !dbg !848
  %t766 = getelementptr inbounds { ptr, i32, i32, i32, i32, [32 x i32] }, ptr %slot27, i32 0, i32 2, !dbg !848
  %t767 = load i32, ptr %t766, !dbg !848
  %t768 = getelementptr inbounds { ptr, i32, i32, i32, i32, [32 x i32] }, ptr %slot27, i32 0, i32 1, !dbg !848
  %t769 = load i32, ptr %t768, !dbg !848
  %t770 = icmp ugt i32 %t764, %t767, !dbg !848
  %t771 = icmp uge i32 %t764, %t769, !dbg !848
  %t772 = or i1 %t770, %t771, !dbg !848
  br i1 %t772, label %lua.raise.244, label %lua.ok.245, !prof !7, !dbg !848
lua.raise.244:
  %t773 = getelementptr inbounds ptr, ptr %t1, i64 11, !dbg !848
  %rt.raise.774 = load ptr, ptr %t773, !invariant.load !8, !dbg !848
  call void %rt.raise.774(ptr %L, i64 8) nomerge, !dbg !848
  unreachable, !dbg !848
lua.ok.245:
  %t775 = icmp eq i32 %t764, %t767, !dbg !848
  %t776 = add i32 %t767, 1, !dbg !848
  %t777 = select i1 %t775, i32 %t776, i32 %t767, !dbg !848
  store i32 %t777, ptr %t766, !dbg !848
  %t778 = getelementptr inbounds { ptr, i32, i32, i32, i32, [32 x i32] }, ptr %slot27, i32 0, i32 0, !dbg !848
  %t779 = load ptr, ptr %t778, !dbg !848
  %t780 = zext i32 %t764 to i64, !dbg !848
  %t781 = getelementptr inbounds i32, ptr %t779, i64 %t780, !dbg !848
  store i32 %t765, ptr %t781, !dbg !848
  store i1 false, ptr %slot36, !dbg !849
  br label %if.end.238, !dbg !849
if.else.240:
  %t782 = load i32, ptr %slot35, !dbg !850
  %t783 = load i32, ptr %slot615, !dbg !850
  %t784 = getelementptr inbounds { ptr, i32, i32, i32, i32, [32 x i32] }, ptr %slot27, i32 0, i32 2, !dbg !850
  %t785 = load i32, ptr %t784, !dbg !850
  %t786 = getelementptr inbounds { ptr, i32, i32, i32, i32, [32 x i32] }, ptr %slot27, i32 0, i32 1, !dbg !850
  %t787 = load i32, ptr %t786, !dbg !850
  %t788 = icmp ugt i32 %t782, %t785, !dbg !850
  %t789 = icmp uge i32 %t782, %t787, !dbg !850
  %t790 = or i1 %t788, %t789, !dbg !850
  br i1 %t790, label %lua.raise.246, label %lua.ok.247, !prof !7, !dbg !850
lua.raise.246:
  %t791 = getelementptr inbounds ptr, ptr %t1, i64 11, !dbg !850
  %rt.raise.792 = load ptr, ptr %t791, !invariant.load !8, !dbg !850
  call void %rt.raise.792(ptr %L, i64 8) nomerge, !dbg !850
  unreachable, !dbg !850
lua.ok.247:
  %t793 = icmp eq i32 %t782, %t785, !dbg !850
  %t794 = add i32 %t785, 1, !dbg !850
  %t795 = select i1 %t793, i32 %t794, i32 %t785, !dbg !850
  store i32 %t795, ptr %t784, !dbg !850
  %t796 = getelementptr inbounds { ptr, i32, i32, i32, i32, [32 x i32] }, ptr %slot27, i32 0, i32 0, !dbg !850
  %t797 = load ptr, ptr %t796, !dbg !850
  %t798 = zext i32 %t782 to i64, !dbg !850
  %t799 = getelementptr inbounds i32, ptr %t797, i64 %t798, !dbg !850
  store i32 %t783, ptr %t799, !dbg !850
  store i1 true, ptr %slot36, !dbg !851
  store i1 false, ptr %slot37, !dbg !852
  br label %if.end.238, !dbg !852
if.end.238:
  %t800 = load i32, ptr %slot35, !dbg !853
  %t801 = add i32 %t800, 1, !dbg !853
  store i32 %t801, ptr %slot35, !dbg !853
  br label %if.end.233, !dbg !853
if.else.237:
  %t802 = load i32, ptr %slot624, !dbg !853
  %t803 = icmp ult i32 %t802, 32, !dbg !853
  br i1 %t803, label %if.then.248, label %if.else.249, !dbg !853
if.then.248:
  %t804 = load i32, ptr %slot624, !dbg !854
  %t805 = icmp eq i32 %t804, 9, !dbg !854
  br i1 %t805, label %or.end.251, label %or.rhs.250, !dbg !854
or.rhs.250:
  %t806 = load i32, ptr %slot624, !dbg !854
  %t807 = icmp eq i32 %t806, 10, !dbg !854
  br label %or.end.251, !dbg !854
or.end.251:
  %t808 = phi i1 [ true, %if.then.248 ], [ %t807, %or.rhs.250 ], !dbg !854
  br i1 %t808, label %or.end.253, label %or.rhs.252, !dbg !854
or.rhs.252:
  %t809 = load i32, ptr %slot624, !dbg !854
  %t810 = icmp eq i32 %t809, 13, !dbg !854
  br label %or.end.253, !dbg !854
or.end.253:
  %t811 = phi i1 [ true, %or.end.251 ], [ %t810, %or.rhs.252 ], !dbg !854
  store i1 %t811, ptr %slot812, !dbg !854
  %t813 = load i1, ptr %slot36, !dbg !855
  br i1 %t813, label %or.end.256, label %or.rhs.255, !dbg !855
or.rhs.255:
  %t814 = load i1, ptr %slot812, !dbg !855
  %t815 = xor i1 %t814, true, !dbg !855
  br label %or.end.256, !dbg !855
or.end.256:
  %t816 = phi i1 [ true, %or.end.253 ], [ %t815, %or.rhs.255 ], !dbg !855
  br i1 %t816, label %if.then.257, label %if.else.258, !dbg !855
if.then.257:
  call void @lua_pushvalue(ptr %L, i32 2), !dbg !856
  %t817 = call i32 @nupp.wrap.u32(double 0x4008000000000000), !dbg !856
  %t818 = uitofp i32 %t817 to double, !dbg !856
  call void @lua_pushnumber(ptr %L, double %t818), !dbg !856
  %t819 = load i32, ptr %slot615, !dbg !856
  %t820 = add i32 %t819, 1, !dbg !856
  %t821 = uitofp i32 %t820 to double, !dbg !856
  call void @lua_pushnumber(ptr %L, double %t821), !dbg !856
  ret i32 3, !dbg !856
if.else.258:
  br label %if.end.254, !dbg !856
if.end.254:
  br label %if.end.233, !dbg !856
if.else.249:
  %t822 = load i1, ptr %slot36, !dbg !856
  %t823 = xor i1 %t822, true, !dbg !856
  br i1 %t823, label %if.then.259, label %if.else.260, !dbg !856
if.then.259:
  %t824 = load i32, ptr %slot35, !dbg !857
  %t825 = load i32, ptr %slot615, !dbg !857
  %t826 = getelementptr inbounds { ptr, i32, i32, i32, i32, [32 x i32] }, ptr %slot27, i32 0, i32 2, !dbg !857
  %t827 = load i32, ptr %t826, !dbg !857
  %t828 = getelementptr inbounds { ptr, i32, i32, i32, i32, [32 x i32] }, ptr %slot27, i32 0, i32 1, !dbg !857
  %t829 = load i32, ptr %t828, !dbg !857
  %t830 = icmp ugt i32 %t824, %t827, !dbg !857
  %t831 = icmp uge i32 %t824, %t829, !dbg !857
  %t832 = or i1 %t830, %t831, !dbg !857
  br i1 %t832, label %lua.raise.261, label %lua.ok.262, !prof !7, !dbg !857
lua.raise.261:
  %t833 = getelementptr inbounds ptr, ptr %t1, i64 11, !dbg !857
  %rt.raise.834 = load ptr, ptr %t833, !invariant.load !8, !dbg !857
  call void %rt.raise.834(ptr %L, i64 8) nomerge, !dbg !857
  unreachable, !dbg !857
lua.ok.262:
  %t835 = icmp eq i32 %t824, %t827, !dbg !857
  %t836 = add i32 %t827, 1, !dbg !857
  %t837 = select i1 %t835, i32 %t836, i32 %t827, !dbg !857
  store i32 %t837, ptr %t826, !dbg !857
  %t838 = getelementptr inbounds { ptr, i32, i32, i32, i32, [32 x i32] }, ptr %slot27, i32 0, i32 0, !dbg !857
  %t839 = load ptr, ptr %t838, !dbg !857
  %t840 = zext i32 %t824 to i64, !dbg !857
  %t841 = getelementptr inbounds i32, ptr %t839, i64 %t840, !dbg !857
  store i32 %t825, ptr %t841, !dbg !857
  %t842 = load i32, ptr %slot35, !dbg !858
  %t843 = add i32 %t842, 1, !dbg !858
  store i32 %t843, ptr %slot35, !dbg !858
  br label %if.end.233, !dbg !858
if.else.260:
  br label %if.end.233, !dbg !858
if.end.233:
  store i1 false, ptr %slot39, !dbg !859
  store i1 false, ptr %slot38, !dbg !860
  br label %if.end.171, !dbg !860
if.end.171:
  br label %if.end.161, !dbg !860
if.else.163:
  br label %if.end.161, !dbg !860
if.end.161:
  br label %while.head.158, !dbg !860
while.end.160:
  %t844 = load i32, ptr %slot33, !dbg !861
  %t845 = load i32, ptr %slot70, !dbg !861
  %t846 = add i32 %t844, %t845, !dbg !861
  store i32 %t846, ptr %slot33, !dbg !861
  br label %while.head.14, !dbg !861
while.end.16:
  br label %cursors.done.13, !dbg !861
cursors.narrow.12:
  br label %while.head.263, !dbg !861
while.head.263:
  %t847 = load i32, ptr %slot33, !dbg !861
  %t848 = load i32, ptr %slot20, !dbg !861
  %t849 = icmp ult i32 %t847, %t848, !dbg !861
  br i1 %t849, label %or.end.267, label %or.rhs.266, !dbg !861
or.rhs.266:
  %t850 = load i1, ptr %slot49, !dbg !861
  %t851 = xor i1 %t850, true, !dbg !861
  br label %or.end.267, !dbg !861
or.end.267:
  %t852 = phi i1 [ true, %while.head.263 ], [ %t851, %or.rhs.266 ], !dbg !861
  br i1 %t852, label %while.body.264, label %while.end.265, !dbg !861
while.body.264:
  %t853 = call i64 @llvm.fptosi.sat.i64.f64(double 0x0000000000000000), !dbg !733
  %t854 = call i64 @llvm.fptoui.sat.i64.f64(double 0x0000000000000000), !dbg !733
  %t855 = fcmp olt double 0x0000000000000000, 0.0, !dbg !733
  %t856 = select i1 %t855, i64 %t853, i64 %t854, !dbg !733
  store i64 %t856, ptr %slot68, !dbg !733
  %t857 = call i32 @nupp.wrap.u32(double 0x0000000000000000), !dbg !734
  store i32 %t857, ptr %slot70, !dbg !734
  br i1 true, label %if.then.269, label %if.else.270, !dbg !735
if.then.269:
  %t858 = load i1, ptr %slot56, !dbg !736
  %t859 = xor i1 %t858, true, !dbg !736
  br i1 %t859, label %and.rhs.272, label %and.end.273, !dbg !736
and.rhs.272:
  %t860 = load i32, ptr %slot33, !dbg !736
  %t861 = zext i32 %t860 to i64, !dbg !736
  %t862 = zext i32 16 to i64, !dbg !736
  %t863 = add i64 %t861, %t862, !dbg !736
  %t864 = load i32, ptr %slot20, !dbg !736
  %t865 = zext i32 %t864 to i64, !dbg !736
  %t866 = icmp ule i64 %t863, %t865, !dbg !736
  br label %and.end.273, !dbg !736
and.end.273:
  %t867 = phi i1 [ false, %if.then.269 ], [ %t866, %and.rhs.272 ], !dbg !736
  br i1 %t867, label %if.then.274, label %if.else.275, !dbg !736
if.then.274:
  %t868 = load i32, ptr %slot33, !dbg !737
  %t869 = zext i32 %t868 to i64, !dbg !737
  %t870 = add nuw i64 %t869, 16, !dbg !737
  %t871 = icmp ule i64 %t870, 4294967295, !dbg !737
  %t872 = add nuw i64 %t869, 0, !dbg !737
  %t873 = getelementptr inbounds nuw i8, ptr %t14, i64 %t872, !dbg !737
  br i1 %t871, label %simd.yes.276, label %simd.no.277, !dbg !737
simd.yes.276:
  %t874 = load <16 x i8>, ptr %t873, align 1, !dbg !737
  br label %simd.join.278, !dbg !737
simd.no.277:
  %t875 = load i32, ptr %slot33, !dbg !737
  %t876 = add i32 %t875, 1, !dbg !737
  %t877 = zext i32 %t876 to i64, !dbg !737
  %t878 = icmp ne i64 %t877, 0, !dbg !737
  %t879 = sub i64 %t877, 1, !dbg !737
  %t880 = select i1 %t878, i64 %t879, i64 -1, !dbg !737
  %t881 = icmp ult i64 %t880, %t15, !dbg !737
  %t882 = sub i64 %t15, %t880, !dbg !737
  %t883 = icmp ult i64 %t882, 16, !dbg !737
  %t884 = select i1 %t883, i64 %t882, i64 16, !dbg !737
  %t885 = select i1 %t881, i64 %t884, i64 0, !dbg !737
  %t886 = trunc i64 %t885 to i32, !dbg !737
  %t887 = select i1 %t881, i64 %t880, i64 0, !dbg !737
  %t888 = getelementptr inbounds i8, ptr %t14, i64 %t887, !dbg !737
  %t889 = icmp eq i32 %t886, 16, !dbg !737
  br i1 %t889, label %simd.yes.279, label %simd.no.280, !dbg !737
simd.yes.279:
  %t890 = load <16 x i8>, ptr %t888, align 1, !dbg !737
  br label %simd.join.281, !dbg !737
simd.no.280:
  switch i32 %t886, label %tail.done.298 [ i32 1, label %tail.lane.282 i32 2, label %tail.lane.283 i32 3, label %tail.lane.284 i32 4, label %tail.lane.285 i32 5, label %tail.lane.286 i32 6, label %tail.lane.287 i32 7, label %tail.lane.288 i32 8, label %tail.lane.289 i32 9, label %tail.lane.290 i32 10, label %tail.lane.291 i32 11, label %tail.lane.292 i32 12, label %tail.lane.293 i32 13, label %tail.lane.294 i32 14, label %tail.lane.295 i32 15, label %tail.lane.296 i32 16, label %tail.lane.297 ], !dbg !737
tail.lane.297:
  %t891 = getelementptr inbounds i8, ptr %t888, i64 15, !dbg !737
  %t892 = load i8, ptr %t891, align 1, !dbg !737
  %t893 = insertelement <16 x i8> zeroinitializer, i8 %t892, i32 15, !dbg !737
  br label %tail.lane.296, !dbg !737
tail.lane.296:
  %t894 = phi <16 x i8> [ zeroinitializer, %simd.no.280 ], [ %t893, %tail.lane.297 ], !dbg !737
  %t895 = getelementptr inbounds i8, ptr %t888, i64 14, !dbg !737
  %t896 = load i8, ptr %t895, align 1, !dbg !737
  %t897 = insertelement <16 x i8> %t894, i8 %t896, i32 14, !dbg !737
  br label %tail.lane.295, !dbg !737
tail.lane.295:
  %t898 = phi <16 x i8> [ zeroinitializer, %simd.no.280 ], [ %t897, %tail.lane.296 ], !dbg !737
  %t899 = getelementptr inbounds i8, ptr %t888, i64 13, !dbg !737
  %t900 = load i8, ptr %t899, align 1, !dbg !737
  %t901 = insertelement <16 x i8> %t898, i8 %t900, i32 13, !dbg !737
  br label %tail.lane.294, !dbg !737
tail.lane.294:
  %t902 = phi <16 x i8> [ zeroinitializer, %simd.no.280 ], [ %t901, %tail.lane.295 ], !dbg !737
  %t903 = getelementptr inbounds i8, ptr %t888, i64 12, !dbg !737
  %t904 = load i8, ptr %t903, align 1, !dbg !737
  %t905 = insertelement <16 x i8> %t902, i8 %t904, i32 12, !dbg !737
  br label %tail.lane.293, !dbg !737
tail.lane.293:
  %t906 = phi <16 x i8> [ zeroinitializer, %simd.no.280 ], [ %t905, %tail.lane.294 ], !dbg !737
  %t907 = getelementptr inbounds i8, ptr %t888, i64 11, !dbg !737
  %t908 = load i8, ptr %t907, align 1, !dbg !737
  %t909 = insertelement <16 x i8> %t906, i8 %t908, i32 11, !dbg !737
  br label %tail.lane.292, !dbg !737
tail.lane.292:
  %t910 = phi <16 x i8> [ zeroinitializer, %simd.no.280 ], [ %t909, %tail.lane.293 ], !dbg !737
  %t911 = getelementptr inbounds i8, ptr %t888, i64 10, !dbg !737
  %t912 = load i8, ptr %t911, align 1, !dbg !737
  %t913 = insertelement <16 x i8> %t910, i8 %t912, i32 10, !dbg !737
  br label %tail.lane.291, !dbg !737
tail.lane.291:
  %t914 = phi <16 x i8> [ zeroinitializer, %simd.no.280 ], [ %t913, %tail.lane.292 ], !dbg !737
  %t915 = getelementptr inbounds i8, ptr %t888, i64 9, !dbg !737
  %t916 = load i8, ptr %t915, align 1, !dbg !737
  %t917 = insertelement <16 x i8> %t914, i8 %t916, i32 9, !dbg !737
  br label %tail.lane.290, !dbg !737
tail.lane.290:
  %t918 = phi <16 x i8> [ zeroinitializer, %simd.no.280 ], [ %t917, %tail.lane.291 ], !dbg !737
  %t919 = getelementptr inbounds i8, ptr %t888, i64 8, !dbg !737
  %t920 = load i8, ptr %t919, align 1, !dbg !737
  %t921 = insertelement <16 x i8> %t918, i8 %t920, i32 8, !dbg !737
  br label %tail.lane.289, !dbg !737
tail.lane.289:
  %t922 = phi <16 x i8> [ zeroinitializer, %simd.no.280 ], [ %t921, %tail.lane.290 ], !dbg !737
  %t923 = getelementptr inbounds i8, ptr %t888, i64 7, !dbg !737
  %t924 = load i8, ptr %t923, align 1, !dbg !737
  %t925 = insertelement <16 x i8> %t922, i8 %t924, i32 7, !dbg !737
  br label %tail.lane.288, !dbg !737
tail.lane.288:
  %t926 = phi <16 x i8> [ zeroinitializer, %simd.no.280 ], [ %t925, %tail.lane.289 ], !dbg !737
  %t927 = getelementptr inbounds i8, ptr %t888, i64 6, !dbg !737
  %t928 = load i8, ptr %t927, align 1, !dbg !737
  %t929 = insertelement <16 x i8> %t926, i8 %t928, i32 6, !dbg !737
  br label %tail.lane.287, !dbg !737
tail.lane.287:
  %t930 = phi <16 x i8> [ zeroinitializer, %simd.no.280 ], [ %t929, %tail.lane.288 ], !dbg !737
  %t931 = getelementptr inbounds i8, ptr %t888, i64 5, !dbg !737
  %t932 = load i8, ptr %t931, align 1, !dbg !737
  %t933 = insertelement <16 x i8> %t930, i8 %t932, i32 5, !dbg !737
  br label %tail.lane.286, !dbg !737
tail.lane.286:
  %t934 = phi <16 x i8> [ zeroinitializer, %simd.no.280 ], [ %t933, %tail.lane.287 ], !dbg !737
  %t935 = getelementptr inbounds i8, ptr %t888, i64 4, !dbg !737
  %t936 = load i8, ptr %t935, align 1, !dbg !737
  %t937 = insertelement <16 x i8> %t934, i8 %t936, i32 4, !dbg !737
  br label %tail.lane.285, !dbg !737
tail.lane.285:
  %t938 = phi <16 x i8> [ zeroinitializer, %simd.no.280 ], [ %t937, %tail.lane.286 ], !dbg !737
  %t939 = getelementptr inbounds i8, ptr %t888, i64 3, !dbg !737
  %t940 = load i8, ptr %t939, align 1, !dbg !737
  %t941 = insertelement <16 x i8> %t938, i8 %t940, i32 3, !dbg !737
  br label %tail.lane.284, !dbg !737
tail.lane.284:
  %t942 = phi <16 x i8> [ zeroinitializer, %simd.no.280 ], [ %t941, %tail.lane.285 ], !dbg !737
  %t943 = getelementptr inbounds i8, ptr %t888, i64 2, !dbg !737
  %t944 = load i8, ptr %t943, align 1, !dbg !737
  %t945 = insertelement <16 x i8> %t942, i8 %t944, i32 2, !dbg !737
  br label %tail.lane.283, !dbg !737
tail.lane.283:
  %t946 = phi <16 x i8> [ zeroinitializer, %simd.no.280 ], [ %t945, %tail.lane.284 ], !dbg !737
  %t947 = getelementptr inbounds i8, ptr %t888, i64 1, !dbg !737
  %t948 = load i8, ptr %t947, align 1, !dbg !737
  %t949 = insertelement <16 x i8> %t946, i8 %t948, i32 1, !dbg !737
  br label %tail.lane.282, !dbg !737
tail.lane.282:
  %t950 = phi <16 x i8> [ zeroinitializer, %simd.no.280 ], [ %t949, %tail.lane.283 ], !dbg !737
  %t951 = getelementptr inbounds i8, ptr %t888, i64 0, !dbg !737
  %t952 = load i8, ptr %t951, align 1, !dbg !737
  %t953 = insertelement <16 x i8> %t950, i8 %t952, i32 0, !dbg !737
  br label %tail.done.298, !dbg !737
tail.done.298:
  %t954 = phi <16 x i8> [ zeroinitializer, %simd.no.280 ], [ %t953, %tail.lane.282 ], !dbg !737
  br label %simd.join.281, !dbg !737
simd.join.281:
  %t955 = phi <16 x i8> [ %t890, %simd.yes.279 ], [ %t954, %tail.done.298 ], !dbg !737
  br label %simd.join.278, !dbg !737
simd.join.278:
  %t956 = phi <16 x i8> [ %t874, %simd.yes.276 ], [ %t955, %simd.join.281 ], !dbg !737
  store <16 x i8> %t956, ptr %slot168, !dbg !737
  %t957 = load <16 x i8>, ptr %slot168, !dbg !738
  %t958 = call i32 @nupp.wrap.u32(double 0x405EC00000000000), !dbg !738
  %t959 = trunc i32 %t958 to i8, !dbg !738
  %t960 = insertelement <16 x i8> poison, i8 %t959, i64 0, !dbg !738
  %t961 = shufflevector <16 x i8> %t960, <16 x i8> poison, <16 x i32> zeroinitializer, !dbg !738
  %t962 = icmp eq <16 x i8> %t957, %t961, !dbg !738
  %t963 = load <16 x i8>, ptr %slot168, !dbg !738
  %t964 = call i32 @nupp.wrap.u32(double 0x405F400000000000), !dbg !738
  %t965 = trunc i32 %t964 to i8, !dbg !738
  %t966 = insertelement <16 x i8> poison, i8 %t965, i64 0, !dbg !738
  %t967 = shufflevector <16 x i8> %t966, <16 x i8> poison, <16 x i32> zeroinitializer, !dbg !738
  %t968 = icmp eq <16 x i8> %t963, %t967, !dbg !738
  %t969 = or <16 x i1> %t962, %t968, !dbg !738
  %t970 = load <16 x i8>, ptr %slot168, !dbg !738
  %t971 = call i32 @nupp.wrap.u32(double 0x4056C00000000000), !dbg !738
  %t972 = trunc i32 %t971 to i8, !dbg !738
  %t973 = insertelement <16 x i8> poison, i8 %t972, i64 0, !dbg !738
  %t974 = shufflevector <16 x i8> %t973, <16 x i8> poison, <16 x i32> zeroinitializer, !dbg !738
  %t975 = icmp eq <16 x i8> %t970, %t974, !dbg !738
  %t976 = or <16 x i1> %t969, %t975, !dbg !738
  %t977 = load <16 x i8>, ptr %slot168, !dbg !738
  %t978 = call i32 @nupp.wrap.u32(double 0x4057400000000000), !dbg !738
  %t979 = trunc i32 %t978 to i8, !dbg !738
  %t980 = insertelement <16 x i8> poison, i8 %t979, i64 0, !dbg !738
  %t981 = shufflevector <16 x i8> %t980, <16 x i8> poison, <16 x i32> zeroinitializer, !dbg !738
  %t982 = icmp eq <16 x i8> %t977, %t981, !dbg !738
  %t983 = or <16 x i1> %t976, %t982, !dbg !738
  store <16 x i1> %t983, ptr %slot196, !dbg !738
  %t984 = load <16 x i8>, ptr %slot168, !dbg !739
  %t985 = call i32 @nupp.wrap.u32(double 0x404D000000000000), !dbg !739
  %t986 = trunc i32 %t985 to i8, !dbg !739
  %t987 = insertelement <16 x i8> poison, i8 %t986, i64 0, !dbg !739
  %t988 = shufflevector <16 x i8> %t987, <16 x i8> poison, <16 x i32> zeroinitializer, !dbg !739
  %t989 = icmp eq <16 x i8> %t984, %t988, !dbg !739
  %t990 = load <16 x i8>, ptr %slot168, !dbg !739
  %t991 = call i32 @nupp.wrap.u32(double 0x4046000000000000), !dbg !739
  %t992 = trunc i32 %t991 to i8, !dbg !739
  %t993 = insertelement <16 x i8> poison, i8 %t992, i64 0, !dbg !739
  %t994 = shufflevector <16 x i8> %t993, <16 x i8> poison, <16 x i32> zeroinitializer, !dbg !739
  %t995 = icmp eq <16 x i8> %t990, %t994, !dbg !739
  %t996 = or <16 x i1> %t989, %t995, !dbg !739
  store <16 x i1> %t996, ptr %slot210, !dbg !739
  %t997 = load <16 x i8>, ptr %slot168, !dbg !740
  %t998 = call i32 @nupp.wrap.u32(double 0x4041000000000000), !dbg !740
  %t999 = trunc i32 %t998 to i8, !dbg !740
  %t1000 = insertelement <16 x i8> poison, i8 %t999, i64 0, !dbg !740
  %t1001 = shufflevector <16 x i8> %t1000, <16 x i8> poison, <16 x i32> zeroinitializer, !dbg !740
  %t1002 = icmp eq <16 x i8> %t997, %t1001, !dbg !740
  %t1003 = load <16 x i8>, ptr %slot168, !dbg !740
  %t1004 = call i32 @nupp.wrap.u32(double 0x4057000000000000), !dbg !740
  %t1005 = trunc i32 %t1004 to i8, !dbg !740
  %t1006 = insertelement <16 x i8> poison, i8 %t1005, i64 0, !dbg !740
  %t1007 = shufflevector <16 x i8> %t1006, <16 x i8> poison, <16 x i32> zeroinitializer, !dbg !740
  %t1008 = icmp eq <16 x i8> %t1003, %t1007, !dbg !740
  %t1009 = or <16 x i1> %t1002, %t1008, !dbg !740
  store <16 x i1> %t1009, ptr %slot224, !dbg !740
  %t1010 = load <16 x i1>, ptr %slot196, !dbg !741
  %t1011 = load <16 x i1>, ptr %slot210, !dbg !741
  %t1012 = or <16 x i1> %t1010, %t1011, !dbg !741
  %t1013 = load <16 x i1>, ptr %slot224, !dbg !741
  %t1014 = or <16 x i1> %t1012, %t1013, !dbg !741
  %t1015 = load <16 x i8>, ptr %slot168, !dbg !741
  %t1016 = call i32 @nupp.wrap.u32(double 0x4040000000000000), !dbg !741
  %t1017 = trunc i32 %t1016 to i8, !dbg !741
  %t1018 = insertelement <16 x i8> poison, i8 %t1017, i64 0, !dbg !741
  %t1019 = shufflevector <16 x i8> %t1018, <16 x i8> poison, <16 x i32> zeroinitializer, !dbg !741
  %t1020 = icmp ult <16 x i8> %t1015, %t1019, !dbg !741
  %t1021 = or <16 x i1> %t1014, %t1020, !dbg !741
  store <16 x i1> %t1021, ptr %slot237, !dbg !741
  store i1 false, ptr %slot238, !dbg !742
  %t1022 = load i1, ptr %slot50, !dbg !743
  br i1 %t1022, label %if.then.300, label %if.else.301, !dbg !743
if.then.300:
  %t1023 = load <16 x i1>, ptr %slot237, !dbg !744
  %t1024 = bitcast <16 x i1> %t1023 to i16, !dbg !744
  %t1025 = zext i16 %t1024 to i64, !dbg !744
  store i64 %t1025, ptr %slot68, !dbg !744
  store i1 true, ptr %slot238, !dbg !745
  br label %if.end.299, !dbg !745
if.else.301:
  %t1026 = load <16 x i8>, ptr %slot168, !dbg !746
  %t1027 = call i32 @nupp.wrap.u32(double 0x4060000000000000), !dbg !746
  %t1028 = trunc i32 %t1027 to i8, !dbg !746
  %t1029 = insertelement <16 x i8> poison, i8 %t1028, i64 0, !dbg !746
  %t1030 = shufflevector <16 x i8> %t1029, <16 x i8> poison, <16 x i32> zeroinitializer, !dbg !746
  %t1031 = icmp uge <16 x i8> %t1026, %t1030, !dbg !746
  store <16 x i1> %t1031, ptr %slot249, !dbg !746
  %t1032 = load <16 x i1>, ptr %slot237, !dbg !747
  %t1033 = load <16 x i1>, ptr %slot249, !dbg !747
  %t1034 = or <16 x i1> %t1032, %t1033, !dbg !747
  %t1035 = bitcast <16 x i1> %t1034 to i16, !dbg !747
  %t1036 = zext i16 %t1035 to i64, !dbg !747
  store i64 %t1036, ptr %slot68, !dbg !747
  %t1037 = load i64, ptr %slot68, !dbg !748
  %t1038 = call i64 @llvm.fptosi.sat.i64.f64(double 0x0000000000000000), !dbg !748
  %t1039 = call i64 @llvm.fptoui.sat.i64.f64(double 0x0000000000000000), !dbg !748
  %t1040 = fcmp olt double 0x0000000000000000, 0.0, !dbg !748
  %t1041 = select i1 %t1040, i64 %t1038, i64 %t1039, !dbg !748
  %t1042 = icmp ne i64 %t1037, %t1041, !dbg !748
  br i1 %t1042, label %if.then.303, label %if.else.304, !dbg !748
if.then.303:
  %t1043 = load <16 x i1>, ptr %slot249, !dbg !749
  %t1044 = sext <16 x i1> %t1043 to <16 x i8>, !dbg !749
  %t1045 = call <16 x i8> asm "", "=w,0"(<16 x i8> %t1044), !dbg !749
  %t1046 = bitcast <16 x i8> %t1045 to <4 x i32>, !dbg !749
  %t1047 = shufflevector <4 x i32> %t1046, <4 x i32> poison, <4 x i32> <i32 0, i32 1, i32 2, i32 3>, !dbg !749
  %t1048 = call <4 x i32> @llvm.aarch64.neon.umaxp.v4i32(<4 x i32> %t1047, <4 x i32> %t1047), !dbg !749
  %t1049 = bitcast <4 x i32> %t1048 to <2 x i64>, !dbg !749
  %t1050 = extractelement <2 x i64> %t1049, i32 0, !dbg !749
  %t1051 = icmp ne i64 %t1050, 0, !dbg !749
  store i1 %t1051, ptr %slot238, !dbg !749
  %t1052 = load i1, ptr %slot238, !dbg !750
  br i1 %t1052, label %if.then.306, label %if.else.307, !dbg !750
if.then.306:
  %t1053 = load <16 x i1>, ptr %slot237, !dbg !751
  %t1054 = bitcast <16 x i1> %t1053 to i16, !dbg !751
  %t1055 = zext i16 %t1054 to i64, !dbg !751
  store i64 %t1055, ptr %slot68, !dbg !751
  br label %if.end.305, !dbg !751
if.else.307:
  br label %if.end.305, !dbg !751
if.end.305:
  br label %if.end.302, !dbg !751
if.else.304:
  br label %if.end.302, !dbg !751
if.end.302:
  br label %if.end.299, !dbg !751
if.end.299:
  %t1056 = load i1, ptr %slot238, !dbg !752
  br i1 %t1056, label %if.then.309, label %if.else.310, !dbg !752
if.then.309:
  %t1057 = load i32, ptr %slot33, !dbg !753
  %t1058 = sub i32 %t1057, 16, !dbg !753
  %t1059 = add i32 %t1058, 1, !dbg !753
  %t1060 = zext i32 %t1059 to i64, !dbg !753
  %t1061 = icmp ne i64 %t1060, 0, !dbg !753
  %t1062 = sub i64 %t1060, 1, !dbg !753
  %t1063 = select i1 %t1061, i64 %t1062, i64 -1, !dbg !753
  %t1064 = icmp ult i64 %t1063, %t15, !dbg !753
  %t1065 = sub i64 %t15, %t1063, !dbg !753
  %t1066 = icmp ult i64 %t1065, 16, !dbg !753
  %t1067 = select i1 %t1066, i64 %t1065, i64 16, !dbg !753
  %t1068 = select i1 %t1064, i64 %t1067, i64 0, !dbg !753
  %t1069 = trunc i64 %t1068 to i32, !dbg !753
  %t1070 = select i1 %t1064, i64 %t1063, i64 0, !dbg !753
  %t1071 = getelementptr inbounds i8, ptr %t14, i64 %t1070, !dbg !753
  %t1072 = icmp eq i32 %t1069, 16, !dbg !753
  br i1 %t1072, label %simd.yes.311, label %simd.no.312, !dbg !753
simd.yes.311:
  %t1073 = load <16 x i8>, ptr %t1071, align 1, !dbg !753
  br label %simd.join.313, !dbg !753
simd.no.312:
  switch i32 %t1069, label %tail.done.330 [ i32 1, label %tail.lane.314 i32 2, label %tail.lane.315 i32 3, label %tail.lane.316 i32 4, label %tail.lane.317 i32 5, label %tail.lane.318 i32 6, label %tail.lane.319 i32 7, label %tail.lane.320 i32 8, label %tail.lane.321 i32 9, label %tail.lane.322 i32 10, label %tail.lane.323 i32 11, label %tail.lane.324 i32 12, label %tail.lane.325 i32 13, label %tail.lane.326 i32 14, label %tail.lane.327 i32 15, label %tail.lane.328 i32 16, label %tail.lane.329 ], !dbg !753
tail.lane.329:
  %t1074 = getelementptr inbounds i8, ptr %t1071, i64 15, !dbg !753
  %t1075 = load i8, ptr %t1074, align 1, !dbg !753
  %t1076 = insertelement <16 x i8> zeroinitializer, i8 %t1075, i32 15, !dbg !753
  br label %tail.lane.328, !dbg !753
tail.lane.328:
  %t1077 = phi <16 x i8> [ zeroinitializer, %simd.no.312 ], [ %t1076, %tail.lane.329 ], !dbg !753
  %t1078 = getelementptr inbounds i8, ptr %t1071, i64 14, !dbg !753
  %t1079 = load i8, ptr %t1078, align 1, !dbg !753
  %t1080 = insertelement <16 x i8> %t1077, i8 %t1079, i32 14, !dbg !753
  br label %tail.lane.327, !dbg !753
tail.lane.327:
  %t1081 = phi <16 x i8> [ zeroinitializer, %simd.no.312 ], [ %t1080, %tail.lane.328 ], !dbg !753
  %t1082 = getelementptr inbounds i8, ptr %t1071, i64 13, !dbg !753
  %t1083 = load i8, ptr %t1082, align 1, !dbg !753
  %t1084 = insertelement <16 x i8> %t1081, i8 %t1083, i32 13, !dbg !753
  br label %tail.lane.326, !dbg !753
tail.lane.326:
  %t1085 = phi <16 x i8> [ zeroinitializer, %simd.no.312 ], [ %t1084, %tail.lane.327 ], !dbg !753
  %t1086 = getelementptr inbounds i8, ptr %t1071, i64 12, !dbg !753
  %t1087 = load i8, ptr %t1086, align 1, !dbg !753
  %t1088 = insertelement <16 x i8> %t1085, i8 %t1087, i32 12, !dbg !753
  br label %tail.lane.325, !dbg !753
tail.lane.325:
  %t1089 = phi <16 x i8> [ zeroinitializer, %simd.no.312 ], [ %t1088, %tail.lane.326 ], !dbg !753
  %t1090 = getelementptr inbounds i8, ptr %t1071, i64 11, !dbg !753
  %t1091 = load i8, ptr %t1090, align 1, !dbg !753
  %t1092 = insertelement <16 x i8> %t1089, i8 %t1091, i32 11, !dbg !753
  br label %tail.lane.324, !dbg !753
tail.lane.324:
  %t1093 = phi <16 x i8> [ zeroinitializer, %simd.no.312 ], [ %t1092, %tail.lane.325 ], !dbg !753
  %t1094 = getelementptr inbounds i8, ptr %t1071, i64 10, !dbg !753
  %t1095 = load i8, ptr %t1094, align 1, !dbg !753
  %t1096 = insertelement <16 x i8> %t1093, i8 %t1095, i32 10, !dbg !753
  br label %tail.lane.323, !dbg !753
tail.lane.323:
  %t1097 = phi <16 x i8> [ zeroinitializer, %simd.no.312 ], [ %t1096, %tail.lane.324 ], !dbg !753
  %t1098 = getelementptr inbounds i8, ptr %t1071, i64 9, !dbg !753
  %t1099 = load i8, ptr %t1098, align 1, !dbg !753
  %t1100 = insertelement <16 x i8> %t1097, i8 %t1099, i32 9, !dbg !753
  br label %tail.lane.322, !dbg !753
tail.lane.322:
  %t1101 = phi <16 x i8> [ zeroinitializer, %simd.no.312 ], [ %t1100, %tail.lane.323 ], !dbg !753
  %t1102 = getelementptr inbounds i8, ptr %t1071, i64 8, !dbg !753
  %t1103 = load i8, ptr %t1102, align 1, !dbg !753
  %t1104 = insertelement <16 x i8> %t1101, i8 %t1103, i32 8, !dbg !753
  br label %tail.lane.321, !dbg !753
tail.lane.321:
  %t1105 = phi <16 x i8> [ zeroinitializer, %simd.no.312 ], [ %t1104, %tail.lane.322 ], !dbg !753
  %t1106 = getelementptr inbounds i8, ptr %t1071, i64 7, !dbg !753
  %t1107 = load i8, ptr %t1106, align 1, !dbg !753
  %t1108 = insertelement <16 x i8> %t1105, i8 %t1107, i32 7, !dbg !753
  br label %tail.lane.320, !dbg !753
tail.lane.320:
  %t1109 = phi <16 x i8> [ zeroinitializer, %simd.no.312 ], [ %t1108, %tail.lane.321 ], !dbg !753
  %t1110 = getelementptr inbounds i8, ptr %t1071, i64 6, !dbg !753
  %t1111 = load i8, ptr %t1110, align 1, !dbg !753
  %t1112 = insertelement <16 x i8> %t1109, i8 %t1111, i32 6, !dbg !753
  br label %tail.lane.319, !dbg !753
tail.lane.319:
  %t1113 = phi <16 x i8> [ zeroinitializer, %simd.no.312 ], [ %t1112, %tail.lane.320 ], !dbg !753
  %t1114 = getelementptr inbounds i8, ptr %t1071, i64 5, !dbg !753
  %t1115 = load i8, ptr %t1114, align 1, !dbg !753
  %t1116 = insertelement <16 x i8> %t1113, i8 %t1115, i32 5, !dbg !753
  br label %tail.lane.318, !dbg !753
tail.lane.318:
  %t1117 = phi <16 x i8> [ zeroinitializer, %simd.no.312 ], [ %t1116, %tail.lane.319 ], !dbg !753
  %t1118 = getelementptr inbounds i8, ptr %t1071, i64 4, !dbg !753
  %t1119 = load i8, ptr %t1118, align 1, !dbg !753
  %t1120 = insertelement <16 x i8> %t1117, i8 %t1119, i32 4, !dbg !753
  br label %tail.lane.317, !dbg !753
tail.lane.317:
  %t1121 = phi <16 x i8> [ zeroinitializer, %simd.no.312 ], [ %t1120, %tail.lane.318 ], !dbg !753
  %t1122 = getelementptr inbounds i8, ptr %t1071, i64 3, !dbg !753
  %t1123 = load i8, ptr %t1122, align 1, !dbg !753
  %t1124 = insertelement <16 x i8> %t1121, i8 %t1123, i32 3, !dbg !753
  br label %tail.lane.316, !dbg !753
tail.lane.316:
  %t1125 = phi <16 x i8> [ zeroinitializer, %simd.no.312 ], [ %t1124, %tail.lane.317 ], !dbg !753
  %t1126 = getelementptr inbounds i8, ptr %t1071, i64 2, !dbg !753
  %t1127 = load i8, ptr %t1126, align 1, !dbg !753
  %t1128 = insertelement <16 x i8> %t1125, i8 %t1127, i32 2, !dbg !753
  br label %tail.lane.315, !dbg !753
tail.lane.315:
  %t1129 = phi <16 x i8> [ zeroinitializer, %simd.no.312 ], [ %t1128, %tail.lane.316 ], !dbg !753
  %t1130 = getelementptr inbounds i8, ptr %t1071, i64 1, !dbg !753
  %t1131 = load i8, ptr %t1130, align 1, !dbg !753
  %t1132 = insertelement <16 x i8> %t1129, i8 %t1131, i32 1, !dbg !753
  br label %tail.lane.314, !dbg !753
tail.lane.314:
  %t1133 = phi <16 x i8> [ zeroinitializer, %simd.no.312 ], [ %t1132, %tail.lane.315 ], !dbg !753
  %t1134 = getelementptr inbounds i8, ptr %t1071, i64 0, !dbg !753
  %t1135 = load i8, ptr %t1134, align 1, !dbg !753
  %t1136 = insertelement <16 x i8> %t1133, i8 %t1135, i32 0, !dbg !753
  br label %tail.done.330, !dbg !753
tail.done.330:
  %t1137 = phi <16 x i8> [ zeroinitializer, %simd.no.312 ], [ %t1136, %tail.lane.314 ], !dbg !753
  br label %simd.join.313, !dbg !753
simd.join.313:
  %t1138 = phi <16 x i8> [ %t1073, %simd.yes.311 ], [ %t1137, %tail.done.330 ], !dbg !753
  store <16 x i8> %t1138, ptr %slot357, !dbg !753
  %t1139 = load <16 x i8>, ptr %slot357, !dbg !754
  %t1140 = load <16 x i8>, ptr %slot168, !dbg !754
  %t1141 = shufflevector <16 x i8> %t1139, <16 x i8> %t1140, <16 x i32> <i32 15, i32 16, i32 17, i32 18, i32 19, i32 20, i32 21, i32 22, i32 23, i32 24, i32 25, i32 26, i32 27, i32 28, i32 29, i32 30>, !dbg !754
  store <16 x i8> %t1141, ptr %slot361, !dbg !754
  %t1142 = load <16 x i8>, ptr %slot357, !dbg !755
  %t1143 = load <16 x i8>, ptr %slot168, !dbg !755
  %t1144 = shufflevector <16 x i8> %t1142, <16 x i8> %t1143, <16 x i32> <i32 14, i32 15, i32 16, i32 17, i32 18, i32 19, i32 20, i32 21, i32 22, i32 23, i32 24, i32 25, i32 26, i32 27, i32 28, i32 29>, !dbg !755
  store <16 x i8> %t1144, ptr %slot365, !dbg !755
  %t1145 = load <16 x i8>, ptr %slot357, !dbg !756
  %t1146 = load <16 x i8>, ptr %slot168, !dbg !756
  %t1147 = shufflevector <16 x i8> %t1145, <16 x i8> %t1146, <16 x i32> <i32 13, i32 14, i32 15, i32 16, i32 17, i32 18, i32 19, i32 20, i32 21, i32 22, i32 23, i32 24, i32 25, i32 26, i32 27, i32 28>, !dbg !756
  store <16 x i8> %t1147, ptr %slot369, !dbg !756
  %t1148 = call i32 @nupp.wrap.u32(double 0x0000000000000000), !dbg !757
  %t1149 = trunc i32 %t1148 to i8, !dbg !757
  %t1150 = insertelement <16 x i8> poison, i8 %t1149, i64 0, !dbg !757
  %t1151 = shufflevector <16 x i8> %t1150, <16 x i8> poison, <16 x i32> zeroinitializer, !dbg !757
  store <16 x i8> %t1151, ptr %slot374, !dbg !757
  %t1152 = load <16 x i8>, ptr %slot374, !dbg !758
  %t1153 = call <16 x i8> @ks___nupp_const_decode_fused_f007fffb3d50ef9f__5f5f6e757070436f6e73745f6465636f646546757365645f66303037666666623364353065663966_helper_nibble_table(<16 x i8> %t1152, i32 2, i32 2, i32 2, i32 2, i32 2, i32 2, i32 2, i32 2, i32 128, i32 128, i32 128, i32 128, i32 33, i32 1, i32 21, i32 73), !dbg !758
  store <16 x i8> %t1153, ptr %slot377, !dbg !758
  %t1154 = load <16 x i8>, ptr %slot374, !dbg !759
  %t1155 = call <16 x i8> @ks___nupp_const_decode_fused_f007fffb3d50ef9f__5f5f6e757070436f6e73745f6465636f646546757365645f66303037666666623364353065663966_helper_nibble_table(<16 x i8> %t1154, i32 231, i32 163, i32 131, i32 131, i32 139, i32 203, i32 203, i32 203, i32 203, i32 203, i32 203, i32 203, i32 203, i32 219, i32 203, i32 203), !dbg !759
  store <16 x i8> %t1155, ptr %slot380, !dbg !759
  %t1156 = load <16 x i8>, ptr %slot374, !dbg !760
  %t1157 = call <16 x i8> @ks___nupp_const_decode_fused_f007fffb3d50ef9f__5f5f6e757070436f6e73745f6465636f646546757365645f66303037666666623364353065663966_helper_nibble_table(<16 x i8> %t1156, i32 1, i32 1, i32 1, i32 1, i32 1, i32 1, i32 1, i32 1, i32 230, i32 174, i32 186, i32 186, i32 1, i32 1, i32 1, i32 1), !dbg !760
  store <16 x i8> %t1157, ptr %slot383, !dbg !760
  %t1158 = load <16 x i8>, ptr %slot377, !dbg !761
  %t1159 = load <16 x i8>, ptr %slot361, !dbg !761
  %t1160 = call i32 @nupp.wrap.u32(double 0x4010000000000000), !dbg !761
  %t1161 = trunc i32 %t1160 to i8, !dbg !761
  %t1162 = insertelement <16 x i8> poison, i8 %t1161, i64 0, !dbg !761
  %t1163 = shufflevector <16 x i8> %t1162, <16 x i8> poison, <16 x i32> zeroinitializer, !dbg !761
  %t1164 = and <16 x i8> %t1163, splat (i8 7), !dbg !761
  %t1165 = lshr <16 x i8> %t1159, %t1164, !dbg !761
  %t1166 = call i32 @nupp.wrap.u32(double 0x3FF0000000000000), !dbg !761
  %t1167 = trunc i32 %t1166 to i8, !dbg !761
  %t1168 = insertelement <16 x i8> poison, i8 %t1167, i64 0, !dbg !761
  %t1169 = shufflevector <16 x i8> %t1168, <16 x i8> poison, <16 x i32> zeroinitializer, !dbg !761
  %t1170 = add <16 x i8> %t1165, %t1169, !dbg !761
  %t1171 = sub <16 x i8> %t1170, splat (i8 1), !dbg !761
  %t1172 = call <16 x i8> @llvm.aarch64.neon.tbl1.v16i8(<16 x i8> %t1158, <16 x i8> %t1171), !dbg !761
  %t1173 = load <16 x i8>, ptr %slot380, !dbg !761
  %t1174 = load <16 x i8>, ptr %slot361, !dbg !761
  %t1175 = call i32 @nupp.wrap.u32(double 0x402E000000000000), !dbg !761
  %t1176 = trunc i32 %t1175 to i8, !dbg !761
  %t1177 = insertelement <16 x i8> poison, i8 %t1176, i64 0, !dbg !761
  %t1178 = shufflevector <16 x i8> %t1177, <16 x i8> poison, <16 x i32> zeroinitializer, !dbg !761
  %t1179 = and <16 x i8> %t1174, %t1178, !dbg !761
  %t1180 = call i32 @nupp.wrap.u32(double 0x3FF0000000000000), !dbg !761
  %t1181 = trunc i32 %t1180 to i8, !dbg !761
  %t1182 = insertelement <16 x i8> poison, i8 %t1181, i64 0, !dbg !761
  %t1183 = shufflevector <16 x i8> %t1182, <16 x i8> poison, <16 x i32> zeroinitializer, !dbg !761
  %t1184 = add <16 x i8> %t1179, %t1183, !dbg !761
  %t1185 = sub <16 x i8> %t1184, splat (i8 1), !dbg !761
  %t1186 = call <16 x i8> @llvm.aarch64.neon.tbl1.v16i8(<16 x i8> %t1173, <16 x i8> %t1185), !dbg !761
  %t1187 = and <16 x i8> %t1172, %t1186, !dbg !761
  %t1188 = load <16 x i8>, ptr %slot383, !dbg !761
  %t1189 = load <16 x i8>, ptr %slot168, !dbg !761
  %t1190 = call i32 @nupp.wrap.u32(double 0x4010000000000000), !dbg !761
  %t1191 = trunc i32 %t1190 to i8, !dbg !761
  %t1192 = insertelement <16 x i8> poison, i8 %t1191, i64 0, !dbg !761
  %t1193 = shufflevector <16 x i8> %t1192, <16 x i8> poison, <16 x i32> zeroinitializer, !dbg !761
  %t1194 = and <16 x i8> %t1193, splat (i8 7), !dbg !761
  %t1195 = lshr <16 x i8> %t1189, %t1194, !dbg !761
  %t1196 = call i32 @nupp.wrap.u32(double 0x3FF0000000000000), !dbg !761
  %t1197 = trunc i32 %t1196 to i8, !dbg !761
  %t1198 = insertelement <16 x i8> poison, i8 %t1197, i64 0, !dbg !761
  %t1199 = shufflevector <16 x i8> %t1198, <16 x i8> poison, <16 x i32> zeroinitializer, !dbg !761
  %t1200 = add <16 x i8> %t1195, %t1199, !dbg !761
  %t1201 = sub <16 x i8> %t1200, splat (i8 1), !dbg !761
  %t1202 = call <16 x i8> @llvm.aarch64.neon.tbl1.v16i8(<16 x i8> %t1188, <16 x i8> %t1201), !dbg !761
  %t1203 = and <16 x i8> %t1187, %t1202, !dbg !761
  store <16 x i8> %t1203, ptr %slot430, !dbg !761
  %t1204 = call i32 @nupp.wrap.u32(double 0x4060000000000000), !dbg !762
  %t1205 = trunc i32 %t1204 to i8, !dbg !762
  %t1206 = insertelement <16 x i8> poison, i8 %t1205, i64 0, !dbg !762
  %t1207 = shufflevector <16 x i8> %t1206, <16 x i8> poison, <16 x i32> zeroinitializer, !dbg !762
  %t1208 = call i32 @nupp.wrap.u32(double 0x0000000000000000), !dbg !762
  %t1209 = trunc i32 %t1208 to i8, !dbg !762
  %t1210 = insertelement <16 x i8> poison, i8 %t1209, i64 0, !dbg !762
  %t1211 = shufflevector <16 x i8> %t1210, <16 x i8> poison, <16 x i32> zeroinitializer, !dbg !762
  %t1212 = load <16 x i8>, ptr %slot365, !dbg !762
  %t1213 = call i32 @nupp.wrap.u32(double 0x406C000000000000), !dbg !762
  %t1214 = trunc i32 %t1213 to i8, !dbg !762
  %t1215 = insertelement <16 x i8> poison, i8 %t1214, i64 0, !dbg !762
  %t1216 = shufflevector <16 x i8> %t1215, <16 x i8> poison, <16 x i32> zeroinitializer, !dbg !762
  %t1217 = icmp uge <16 x i8> %t1212, %t1216, !dbg !762
  %t1218 = load <16 x i8>, ptr %slot369, !dbg !762
  %t1219 = call i32 @nupp.wrap.u32(double 0x406E000000000000), !dbg !762
  %t1220 = trunc i32 %t1219 to i8, !dbg !762
  %t1221 = insertelement <16 x i8> poison, i8 %t1220, i64 0, !dbg !762
  %t1222 = shufflevector <16 x i8> %t1221, <16 x i8> poison, <16 x i32> zeroinitializer, !dbg !762
  %t1223 = icmp uge <16 x i8> %t1218, %t1222, !dbg !762
  %t1224 = or <16 x i1> %t1217, %t1223, !dbg !762
  %t1225 = select <16 x i1> %t1224, <16 x i8> %t1207, <16 x i8> %t1211, !dbg !762
  store <16 x i8> %t1225, ptr %slot453, !dbg !762
  %t1226 = load <16 x i8>, ptr %slot430, !dbg !763
  %t1227 = load <16 x i8>, ptr %slot453, !dbg !763
  %t1228 = xor <16 x i8> %t1226, %t1227, !dbg !763
  %t1229 = call i32 @nupp.wrap.u32(double 0x0000000000000000), !dbg !763
  %t1230 = trunc i32 %t1229 to i8, !dbg !763
  %t1231 = zext i8 %t1230 to i32, !dbg !763
  %t1232 = call i32 @llvm.aarch64.neon.umaxv.i32.v16i8(<16 x i8> %t1228), !dbg !763
  %t1233 = trunc i32 %t1232 to i8, !dbg !763
  %t1234 = zext i8 %t1233 to i32, !dbg !763
  %t1235 = icmp ne i32 %t1234, 0, !dbg !763
  br i1 %t1235, label %if.then.332, label %if.else.333, !dbg !763
if.then.332:
  store i1 true, ptr %slot56, !dbg !764
  br label %if.end.331, !dbg !764
if.else.333:
  %t1236 = load <16 x i8>, ptr %slot168, !dbg !765
  %t1237 = load <16 x i8>, ptr %slot168, !dbg !765
  %t1238 = shufflevector <16 x i8> %t1236, <16 x i8> %t1237, <16 x i32> <i32 15, i32 16, i32 17, i32 18, i32 19, i32 20, i32 21, i32 22, i32 23, i32 24, i32 25, i32 26, i32 27, i32 28, i32 29, i32 30>, !dbg !765
  %t1239 = extractelement <16 x i8> %t1238, i32 0, !dbg !765
  %t1240 = zext i8 %t1239 to i32, !dbg !765
  %t1241 = icmp uge i32 %t1240, 128, !dbg !765
  store i1 %t1241, ptr %slot50, !dbg !765
  br label %if.end.331, !dbg !765
if.end.331:
  br label %if.end.308, !dbg !765
if.else.310:
  store i1 false, ptr %slot50, !dbg !766
  br label %if.end.308, !dbg !766
if.end.308:
  %t1242 = load i1, ptr %slot56, !dbg !767
  %t1243 = xor i1 %t1242, true, !dbg !767
  br i1 %t1243, label %if.then.335, label %if.else.336, !dbg !767
if.then.335:
  store i32 16, ptr %slot70, !dbg !768
  br label %if.end.334, !dbg !768
if.else.336:
  %t1244 = call i64 @llvm.fptosi.sat.i64.f64(double 0x0000000000000000), !dbg !769
  %t1245 = call i64 @llvm.fptoui.sat.i64.f64(double 0x0000000000000000), !dbg !769
  %t1246 = fcmp olt double 0x0000000000000000, 0.0, !dbg !769
  %t1247 = select i1 %t1246, i64 %t1244, i64 %t1245, !dbg !769
  store i64 %t1247, ptr %slot68, !dbg !769
  br label %if.end.334, !dbg !769
if.end.334:
  br label %if.end.271, !dbg !769
if.else.275:
  br label %if.end.271, !dbg !769
if.end.271:
  br label %if.end.268, !dbg !769
if.else.270:
  br label %if.end.268, !dbg !769
if.end.268:
  %t1248 = load i32, ptr %slot70, !dbg !770
  %t1249 = icmp eq i32 %t1248, 0, !dbg !770
  br i1 %t1249, label %and.rhs.338, label %and.end.339, !dbg !770
and.rhs.338:
  %t1250 = load i1, ptr %slot49, !dbg !770
  %t1251 = xor i1 %t1250, true, !dbg !770
  br label %and.end.339, !dbg !770
and.end.339:
  %t1252 = phi i1 [ false, %if.end.268 ], [ %t1251, %and.rhs.338 ], !dbg !770
  br i1 %t1252, label %if.then.340, label %if.else.341, !dbg !770
if.then.340:
  store i1 true, ptr %slot49, !dbg !771
  %t1253 = call i32 @nupp.wrap.u32(double 0x3FF0000000000000), !dbg !772
  store i32 %t1253, ptr %slot482, !dbg !772
  store i1 true, ptr %slot483, !dbg !773
  br label %while.head.342, !dbg !774
while.head.342:
  %t1254 = load i1, ptr %slot483, !dbg !774
  br i1 %t1254, label %and.rhs.345, label %and.end.346, !dbg !774
and.rhs.345:
  %t1255 = load i32, ptr %slot482, !dbg !774
  %t1256 = icmp ule i32 %t1255, 3, !dbg !774
  br label %and.end.346, !dbg !774
and.end.346:
  %t1257 = phi i1 [ false, %while.head.342 ], [ %t1256, %and.rhs.345 ], !dbg !774
  br i1 %t1257, label %and.rhs.347, label %and.end.348, !dbg !774
and.rhs.347:
  %t1258 = load i32, ptr %slot482, !dbg !774
  %t1259 = load i32, ptr %slot33, !dbg !774
  %t1260 = icmp ule i32 %t1258, %t1259, !dbg !774
  br label %and.end.348, !dbg !774
and.end.348:
  %t1261 = phi i1 [ false, %and.end.346 ], [ %t1260, %and.rhs.347 ], !dbg !774
  br i1 %t1261, label %while.body.343, label %while.end.344, !dbg !774
while.body.343:
  %t1262 = load i32, ptr %slot33, !dbg !775
  %t1263 = load i32, ptr %slot482, !dbg !775
  %t1264 = sub i32 %t1262, %t1263, !dbg !775
  %t1265 = zext i32 %t1264 to i64, !dbg !775
  %t1266 = icmp uge i64 %t1265, %t15, !dbg !775
  br i1 %t1266, label %lua.raise.349, label %lua.ok.350, !prof !7, !dbg !775
lua.raise.349:
  %t1267 = getelementptr inbounds ptr, ptr %t1, i64 11, !dbg !775
  %rt.raise.1268 = load ptr, ptr %t1267, !invariant.load !8, !dbg !775
  call void %rt.raise.1268(ptr %L, i64 3) nomerge, !dbg !775
  unreachable, !dbg !775
lua.ok.350:
  %t1269 = getelementptr inbounds i8, ptr %t14, i64 %t1265, !dbg !775
  %t1270 = load i8, ptr %t1269, !dbg !775
  %t1271 = zext i8 %t1270 to i32, !dbg !775
  store i32 %t1271, ptr %slot502, !dbg !775
  %t1272 = load i32, ptr %slot502, !dbg !776
  %t1273 = icmp ult i32 %t1272, 128, !dbg !776
  br i1 %t1273, label %if.then.352, label %if.else.353, !dbg !776
if.then.352:
  store i1 false, ptr %slot483, !dbg !777
  br label %if.end.351, !dbg !777
if.else.353:
  %t1274 = load i32, ptr %slot502, !dbg !777
  %t1275 = icmp uge i32 %t1274, 192, !dbg !777
  br i1 %t1275, label %if.then.354, label %if.else.355, !dbg !777
if.then.354:
  %t1276 = load i32, ptr %slot502, !dbg !778
  %t1277 = icmp ult i32 %t1276, 194, !dbg !778
  br i1 %t1277, label %or.end.358, label %or.rhs.357, !dbg !778
or.rhs.357:
  %t1278 = load i32, ptr %slot502, !dbg !778
  %t1279 = icmp ugt i32 %t1278, 244, !dbg !778
  br label %or.end.358, !dbg !778
or.end.358:
  %t1280 = phi i1 [ true, %if.then.354 ], [ %t1279, %or.rhs.357 ], !dbg !778
  br i1 %t1280, label %if.then.359, label %if.else.360, !dbg !778
if.then.359:
  call void @lua_pushvalue(ptr %L, i32 2), !dbg !779
  %t1281 = call i32 @nupp.wrap.u32(double 0x4000000000000000), !dbg !779
  %t1282 = uitofp i32 %t1281 to double, !dbg !779
  call void @lua_pushnumber(ptr %L, double %t1282), !dbg !779
  %t1283 = load i32, ptr %slot33, !dbg !779
  %t1284 = load i32, ptr %slot482, !dbg !779
  %t1285 = sub i32 %t1283, %t1284, !dbg !779
  %t1286 = add i32 %t1285, 1, !dbg !779
  %t1287 = uitofp i32 %t1286 to double, !dbg !779
  call void @lua_pushnumber(ptr %L, double %t1287), !dbg !779
  ret i32 3, !dbg !779
if.else.360:
  br label %if.end.356, !dbg !779
if.end.356:
  %t1288 = call i32 @nupp.wrap.u32(double 0x4008000000000000), !dbg !780
  store i32 %t1288, ptr %slot520, !dbg !780
  %t1289 = load i32, ptr %slot502, !dbg !781
  %t1290 = icmp ule i32 %t1289, 223, !dbg !781
  br i1 %t1290, label %if.then.362, label %if.else.363, !dbg !781
if.then.362:
  %t1291 = call i32 @nupp.wrap.u32(double 0x3FF0000000000000), !dbg !782
  store i32 %t1291, ptr %slot520, !dbg !782
  br label %if.end.361, !dbg !782
if.else.363:
  %t1292 = load i32, ptr %slot502, !dbg !782
  %t1293 = icmp ule i32 %t1292, 239, !dbg !782
  br i1 %t1293, label %if.then.364, label %if.else.365, !dbg !782
if.then.364:
  %t1294 = call i32 @nupp.wrap.u32(double 0x4000000000000000), !dbg !783
  store i32 %t1294, ptr %slot520, !dbg !783
  br label %if.end.361, !dbg !783
if.else.365:
  br label %if.end.361, !dbg !783
if.end.361:
  %t1295 = load i32, ptr %slot520, !dbg !784
  %t1296 = load i32, ptr %slot482, !dbg !784
  %t1297 = icmp uge i32 %t1295, %t1296, !dbg !784
  br i1 %t1297, label %if.then.367, label %if.else.368, !dbg !784
if.then.367:
  %t1298 = load i32, ptr %slot520, !dbg !785
  %t1299 = load i32, ptr %slot482, !dbg !785
  %t1300 = sub i32 %t1298, %t1299, !dbg !785
  %t1301 = add i32 %t1300, 1, !dbg !785
  store i32 %t1301, ptr %slot43, !dbg !785
  store i1 true, ptr %slot46, !dbg !786
  %t1302 = load i32, ptr %slot33, !dbg !787
  %t1303 = sub i32 %t1302, 1, !dbg !787
  store i32 %t1303, ptr %slot48, !dbg !787
  %t1304 = load i32, ptr %slot482, !dbg !788
  %t1305 = icmp eq i32 %t1304, 1, !dbg !788
  br i1 %t1305, label %if.then.370, label %if.else.371, !dbg !788
if.then.370:
  %t1306 = load i32, ptr %slot502, !dbg !789
  %t1307 = icmp eq i32 %t1306, 224, !dbg !789
  br i1 %t1307, label %if.then.373, label %if.else.374, !dbg !789
if.then.373:
  %t1308 = call i32 @nupp.wrap.u32(double 0x3FF0000000000000), !dbg !790
  store i32 %t1308, ptr %slot45, !dbg !790
  br label %if.end.372, !dbg !790
if.else.374:
  %t1309 = load i32, ptr %slot502, !dbg !790
  %t1310 = icmp eq i32 %t1309, 237, !dbg !790
  br i1 %t1310, label %if.then.375, label %if.else.376, !dbg !790
if.then.375:
  %t1311 = call i32 @nupp.wrap.u32(double 0x4000000000000000), !dbg !791
  store i32 %t1311, ptr %slot45, !dbg !791
  br label %if.end.372, !dbg !791
if.else.376:
  %t1312 = load i32, ptr %slot502, !dbg !791
  %t1313 = icmp eq i32 %t1312, 240, !dbg !791
  br i1 %t1313, label %if.then.377, label %if.else.378, !dbg !791
if.then.377:
  %t1314 = call i32 @nupp.wrap.u32(double 0x4008000000000000), !dbg !792
  store i32 %t1314, ptr %slot45, !dbg !792
  br label %if.end.372, !dbg !792
if.else.378:
  %t1315 = load i32, ptr %slot502, !dbg !792
  %t1316 = icmp eq i32 %t1315, 244, !dbg !792
  br i1 %t1316, label %if.then.379, label %if.else.380, !dbg !792
if.then.379:
  %t1317 = call i32 @nupp.wrap.u32(double 0x4010000000000000), !dbg !793
  store i32 %t1317, ptr %slot45, !dbg !793
  br label %if.end.372, !dbg !793
if.else.380:
  br label %if.end.372, !dbg !793
if.end.372:
  br label %if.end.369, !dbg !793
if.else.371:
  br label %if.end.369, !dbg !793
if.end.369:
  br label %if.end.366, !dbg !793
if.else.368:
  br label %if.end.366, !dbg !793
if.end.366:
  store i1 false, ptr %slot483, !dbg !794
  br label %if.end.351, !dbg !794
if.else.355:
  %t1318 = load i32, ptr %slot482, !dbg !795
  %t1319 = add i32 %t1318, 1, !dbg !795
  store i32 %t1319, ptr %slot482, !dbg !795
  br label %if.end.351, !dbg !795
if.end.351:
  br label %while.head.342, !dbg !795
while.end.344:
  br label %if.end.337, !dbg !795
if.else.341:
  %t1320 = load i32, ptr %slot70, !dbg !795
  %t1321 = icmp eq i32 %t1320, 0, !dbg !795
  br i1 %t1321, label %if.then.381, label %if.else.382, !dbg !795
if.then.381:
  %t1322 = load i32, ptr %slot33, !dbg !796
  %t1323 = load i32, ptr %slot20, !dbg !796
  %t1324 = icmp ult i32 %t1322, %t1323, !dbg !796
  br i1 %t1324, label %if.then.384, label %if.else.385, !dbg !796
if.then.384:
  %t1325 = load i32, ptr %slot33, !dbg !797
  %t1326 = zext i32 %t1325 to i64, !dbg !797
  %t1327 = getelementptr inbounds i8, ptr %t14, i64 %t1326, !dbg !797
  %t1328 = load i8, ptr %t1327, !dbg !797
  %t1329 = zext i8 %t1328 to i32, !dbg !797
  store i32 %t1329, ptr %slot562, !dbg !797
  %t1330 = load i32, ptr %slot562, !dbg !798
  %t1331 = icmp eq i32 %t1330, 34, !dbg !798
  br i1 %t1331, label %or.end.388, label %or.rhs.387, !dbg !798
or.rhs.387:
  %t1332 = load i32, ptr %slot562, !dbg !798
  %t1333 = icmp eq i32 %t1332, 92, !dbg !798
  br label %or.end.388, !dbg !798
or.end.388:
  %t1334 = phi i1 [ true, %if.then.384 ], [ %t1333, %or.rhs.387 ], !dbg !798
  br i1 %t1334, label %or.end.390, label %or.rhs.389, !dbg !798
or.rhs.389:
  %t1335 = load i32, ptr %slot562, !dbg !798
  %t1336 = icmp ult i32 %t1335, 32, !dbg !798
  br label %or.end.390, !dbg !798
or.end.390:
  %t1337 = phi i1 [ true, %or.end.388 ], [ %t1336, %or.rhs.389 ], !dbg !798
  br i1 %t1337, label %or.end.392, label %or.rhs.391, !dbg !798
or.rhs.391:
  %t1338 = load i32, ptr %slot562, !dbg !798
  %t1339 = icmp eq i32 %t1338, 123, !dbg !798
  br label %or.end.392, !dbg !798
or.end.392:
  %t1340 = phi i1 [ true, %or.end.390 ], [ %t1339, %or.rhs.391 ], !dbg !798
  br i1 %t1340, label %or.end.394, label %or.rhs.393, !dbg !798
or.rhs.393:
  %t1341 = load i32, ptr %slot562, !dbg !798
  %t1342 = icmp eq i32 %t1341, 125, !dbg !798
  br label %or.end.394, !dbg !798
or.end.394:
  %t1343 = phi i1 [ true, %or.end.392 ], [ %t1342, %or.rhs.393 ], !dbg !798
  br i1 %t1343, label %or.end.396, label %or.rhs.395, !dbg !798
or.rhs.395:
  %t1344 = load i32, ptr %slot562, !dbg !798
  %t1345 = icmp eq i32 %t1344, 91, !dbg !798
  br label %or.end.396, !dbg !798
or.end.396:
  %t1346 = phi i1 [ true, %or.end.394 ], [ %t1345, %or.rhs.395 ], !dbg !798
  br i1 %t1346, label %or.end.398, label %or.rhs.397, !dbg !798
or.rhs.397:
  %t1347 = load i32, ptr %slot562, !dbg !798
  %t1348 = icmp eq i32 %t1347, 93, !dbg !798
  br label %or.end.398, !dbg !798
or.end.398:
  %t1349 = phi i1 [ true, %or.end.396 ], [ %t1348, %or.rhs.397 ], !dbg !798
  br i1 %t1349, label %or.end.400, label %or.rhs.399, !dbg !798
or.rhs.399:
  %t1350 = load i32, ptr %slot562, !dbg !798
  %t1351 = icmp eq i32 %t1350, 58, !dbg !798
  br label %or.end.400, !dbg !798
or.end.400:
  %t1352 = phi i1 [ true, %or.end.398 ], [ %t1351, %or.rhs.399 ], !dbg !798
  br i1 %t1352, label %or.end.402, label %or.rhs.401, !dbg !798
or.rhs.401:
  %t1353 = load i32, ptr %slot562, !dbg !798
  %t1354 = icmp eq i32 %t1353, 44, !dbg !798
  br label %or.end.402, !dbg !798
or.end.402:
  %t1355 = phi i1 [ true, %or.end.400 ], [ %t1354, %or.rhs.401 ], !dbg !798
  br i1 %t1355, label %or.end.404, label %or.rhs.403, !dbg !798
or.rhs.403:
  %t1356 = load i32, ptr %slot562, !dbg !798
  %t1357 = icmp uge i32 %t1356, 128, !dbg !798
  br label %or.end.404, !dbg !798
or.end.404:
  %t1358 = phi i1 [ true, %or.end.402 ], [ %t1357, %or.rhs.403 ], !dbg !798
  br i1 %t1358, label %if.then.405, label %if.else.406, !dbg !798
if.then.405:
  %t1359 = load i64, ptr %slot55, !dbg !799
  store i64 %t1359, ptr %slot68, !dbg !799
  br label %if.end.386, !dbg !799
if.else.406:
  br label %if.end.386, !dbg !799
if.end.386:
  br label %if.end.383, !dbg !799
if.else.385:
  br label %if.end.383, !dbg !799
if.end.383:
  %t1360 = call i32 @nupp.wrap.u32(double 0x3FF0000000000000), !dbg !800
  store i32 %t1360, ptr %slot70, !dbg !800
  br label %if.end.337, !dbg !800
if.else.382:
  br label %if.end.337, !dbg !800
if.end.337:
  br label %while.head.407, !dbg !801
while.head.407:
  %t1361 = load i64, ptr %slot68, !dbg !801
  %t1362 = call i64 @llvm.fptosi.sat.i64.f64(double 0x0000000000000000), !dbg !801
  %t1363 = call i64 @llvm.fptoui.sat.i64.f64(double 0x0000000000000000), !dbg !801
  %t1364 = fcmp olt double 0x0000000000000000, 0.0, !dbg !801
  %t1365 = select i1 %t1364, i64 %t1362, i64 %t1363, !dbg !801
  %t1366 = icmp ne i64 %t1361, %t1365, !dbg !801
  br i1 %t1366, label %while.body.408, label %while.end.409, !dbg !801
while.body.408:
  %t1367 = load i64, ptr %slot68, !dbg !802
  %t1368 = call i64 @llvm.cttz.i64(i64 %t1367, i1 false), !dbg !802
  %t1369 = trunc i64 %t1368 to i32, !dbg !802
  store i32 %t1369, ptr %slot603, !dbg !802
  %t1370 = load i64, ptr %slot68, !dbg !803
  %t1371 = load i64, ptr %slot68, !dbg !803
  %t1372 = call i64 @llvm.fptosi.sat.i64.f64(double 0x3FF0000000000000), !dbg !803
  %t1373 = call i64 @llvm.fptoui.sat.i64.f64(double 0x3FF0000000000000), !dbg !803
  %t1374 = fcmp olt double 0x3FF0000000000000, 0.0, !dbg !803
  %t1375 = select i1 %t1374, i64 %t1372, i64 %t1373, !dbg !803
  %t1376 = sub i64 %t1371, %t1375, !dbg !803
  %t1377 = and i64 %t1370, %t1376, !dbg !803
  store i64 %t1377, ptr %slot68, !dbg !803
  %t1378 = load i32, ptr %slot33, !dbg !804
  %t1379 = load i32, ptr %slot603, !dbg !804
  %t1380 = add i32 %t1378, %t1379, !dbg !804
  store i32 %t1380, ptr %slot615, !dbg !804
  %t1381 = load i32, ptr %slot615, !dbg !805
  %t1382 = load i32, ptr %slot20, !dbg !805
  %t1383 = icmp ult i32 %t1381, %t1382, !dbg !805
  br i1 %t1383, label %if.then.411, label %if.else.412, !dbg !805
if.then.411:
  %t1384 = load i32, ptr %slot615, !dbg !806
  %t1385 = zext i32 %t1384 to i64, !dbg !806
  %t1386 = getelementptr inbounds i8, ptr %t14, i64 %t1385, !dbg !806
  %t1387 = load i8, ptr %t1386, !dbg !806
  %t1388 = zext i8 %t1387 to i32, !dbg !806
  store i32 %t1388, ptr %slot624, !dbg !806
  %t1389 = load i32, ptr %slot43, !dbg !807
  %t1390 = icmp ne i32 %t1389, 0, !dbg !807
  br i1 %t1390, label %and.rhs.414, label %and.end.415, !dbg !807
and.rhs.414:
  %t1391 = load i1, ptr %slot46, !dbg !807
  %t1392 = xor i1 %t1391, true, !dbg !807
  br i1 %t1392, label %or.end.417, label %or.rhs.416, !dbg !807
or.rhs.416:
  %t1393 = load i32, ptr %slot615, !dbg !807
  %t1394 = load i32, ptr %slot48, !dbg !807
  %t1395 = add i32 %t1394, 1, !dbg !807
  %t1396 = icmp ne i32 %t1393, %t1395, !dbg !807
  br label %or.end.417, !dbg !807
or.end.417:
  %t1397 = phi i1 [ true, %and.rhs.414 ], [ %t1396, %or.rhs.416 ], !dbg !807
  br label %and.end.415, !dbg !807
and.end.415:
  %t1398 = phi i1 [ false, %if.then.411 ], [ %t1397, %or.end.417 ], !dbg !807
  br i1 %t1398, label %if.then.418, label %if.else.419, !dbg !807
if.then.418:
  call void @lua_pushvalue(ptr %L, i32 2), !dbg !808
  %t1399 = call i32 @nupp.wrap.u32(double 0x4000000000000000), !dbg !808
  %t1400 = uitofp i32 %t1399 to double, !dbg !808
  call void @lua_pushnumber(ptr %L, double %t1400), !dbg !808
  %t1401 = load i32, ptr %slot48, !dbg !808
  %t1402 = add i32 %t1401, 2, !dbg !808
  %t1403 = uitofp i32 %t1402 to double, !dbg !808
  call void @lua_pushnumber(ptr %L, double %t1403), !dbg !808
  ret i32 3, !dbg !808
if.else.419:
  br label %if.end.413, !dbg !808
if.end.413:
  %t1404 = load i32, ptr %slot624, !dbg !809
  %t1405 = icmp uge i32 %t1404, 128, !dbg !809
  br i1 %t1405, label %if.then.421, label %if.else.422, !dbg !809
if.then.421:
  %t1406 = load i32, ptr %slot624, !dbg !810
  %t1407 = icmp ule i32 %t1406, 191, !dbg !810
  store i1 %t1407, ptr %slot644, !dbg !810
  %t1408 = load i32, ptr %slot43, !dbg !811
  %t1409 = icmp ne i32 %t1408, 0, !dbg !811
  br i1 %t1409, label %if.then.424, label %if.else.425, !dbg !811
if.then.424:
  %t1410 = load i1, ptr %slot644, !dbg !812
  %t1411 = xor i1 %t1410, true, !dbg !812
  br i1 %t1411, label %if.then.427, label %if.else.428, !dbg !812
if.then.427:
  call void @lua_pushvalue(ptr %L, i32 2), !dbg !813
  %t1412 = call i32 @nupp.wrap.u32(double 0x4000000000000000), !dbg !813
  %t1413 = uitofp i32 %t1412 to double, !dbg !813
  call void @lua_pushnumber(ptr %L, double %t1413), !dbg !813
  %t1414 = load i32, ptr %slot615, !dbg !813
  %t1415 = add i32 %t1414, 1, !dbg !813
  %t1416 = uitofp i32 %t1415 to double, !dbg !813
  call void @lua_pushnumber(ptr %L, double %t1416), !dbg !813
  ret i32 3, !dbg !813
if.else.428:
  br label %if.end.426, !dbg !813
if.end.426:
  %t1417 = load i32, ptr %slot45, !dbg !814
  %t1418 = icmp eq i32 %t1417, 1, !dbg !814
  br i1 %t1418, label %and.rhs.429, label %and.end.430, !dbg !814
and.rhs.429:
  %t1419 = load i32, ptr %slot624, !dbg !814
  %t1420 = icmp ult i32 %t1419, 160, !dbg !814
  br label %and.end.430, !dbg !814
and.end.430:
  %t1421 = phi i1 [ false, %if.end.426 ], [ %t1420, %and.rhs.429 ], !dbg !814
  br i1 %t1421, label %or.end.432, label %or.rhs.431, !dbg !814
or.rhs.431:
  %t1422 = load i32, ptr %slot45, !dbg !814
  %t1423 = icmp eq i32 %t1422, 2, !dbg !814
  br i1 %t1423, label %and.rhs.433, label %and.end.434, !dbg !814
and.rhs.433:
  %t1424 = load i32, ptr %slot624, !dbg !814
  %t1425 = icmp ugt i32 %t1424, 159, !dbg !814
  br label %and.end.434, !dbg !814
and.end.434:
  %t1426 = phi i1 [ false, %or.rhs.431 ], [ %t1425, %and.rhs.433 ], !dbg !814
  br label %or.end.432, !dbg !814
or.end.432:
  %t1427 = phi i1 [ true, %and.end.430 ], [ %t1426, %and.end.434 ], !dbg !814
  br i1 %t1427, label %or.end.436, label %or.rhs.435, !dbg !814
or.rhs.435:
  %t1428 = load i32, ptr %slot45, !dbg !814
  %t1429 = icmp eq i32 %t1428, 3, !dbg !814
  br i1 %t1429, label %and.rhs.437, label %and.end.438, !dbg !814
and.rhs.437:
  %t1430 = load i32, ptr %slot624, !dbg !814
  %t1431 = icmp ult i32 %t1430, 144, !dbg !814
  br label %and.end.438, !dbg !814
and.end.438:
  %t1432 = phi i1 [ false, %or.rhs.435 ], [ %t1431, %and.rhs.437 ], !dbg !814
  br label %or.end.436, !dbg !814
or.end.436:
  %t1433 = phi i1 [ true, %or.end.432 ], [ %t1432, %and.end.438 ], !dbg !814
  br i1 %t1433, label %or.end.440, label %or.rhs.439, !dbg !814
or.rhs.439:
  %t1434 = load i32, ptr %slot45, !dbg !814
  %t1435 = icmp eq i32 %t1434, 4, !dbg !814
  br i1 %t1435, label %and.rhs.441, label %and.end.442, !dbg !814
and.rhs.441:
  %t1436 = load i32, ptr %slot624, !dbg !814
  %t1437 = icmp ugt i32 %t1436, 143, !dbg !814
  br label %and.end.442, !dbg !814
and.end.442:
  %t1438 = phi i1 [ false, %or.rhs.439 ], [ %t1437, %and.rhs.441 ], !dbg !814
  br label %or.end.440, !dbg !814
or.end.440:
  %t1439 = phi i1 [ true, %or.end.436 ], [ %t1438, %and.end.442 ], !dbg !814
  store i1 %t1439, ptr %slot677, !dbg !814
  %t1440 = load i1, ptr %slot677, !dbg !815
  br i1 %t1440, label %if.then.444, label %if.else.445, !dbg !815
if.then.444:
  call void @lua_pushvalue(ptr %L, i32 2), !dbg !816
  %t1441 = call i32 @nupp.wrap.u32(double 0x4000000000000000), !dbg !816
  %t1442 = uitofp i32 %t1441 to double, !dbg !816
  call void @lua_pushnumber(ptr %L, double %t1442), !dbg !816
  %t1443 = load i32, ptr %slot615, !dbg !816
  %t1444 = add i32 %t1443, 1, !dbg !816
  %t1445 = uitofp i32 %t1444 to double, !dbg !816
  call void @lua_pushnumber(ptr %L, double %t1445), !dbg !816
  ret i32 3, !dbg !816
if.else.445:
  br label %if.end.443, !dbg !816
if.end.443:
  %t1446 = load i32, ptr %slot43, !dbg !817
  %t1447 = sub i32 %t1446, 1, !dbg !817
  store i32 %t1447, ptr %slot43, !dbg !817
  %t1448 = call i32 @nupp.wrap.u32(double 0x0000000000000000), !dbg !818
  store i32 %t1448, ptr %slot45, !dbg !818
  br label %if.end.423, !dbg !818
if.else.425:
  %t1449 = load i1, ptr %slot644, !dbg !818
  br i1 %t1449, label %or.end.447, label %or.rhs.446, !dbg !818
or.rhs.446:
  %t1450 = load i32, ptr %slot624, !dbg !818
  %t1451 = icmp ult i32 %t1450, 194, !dbg !818
  br label %or.end.447, !dbg !818
or.end.447:
  %t1452 = phi i1 [ true, %if.else.425 ], [ %t1451, %or.rhs.446 ], !dbg !818
  br i1 %t1452, label %or.end.449, label %or.rhs.448, !dbg !818
or.rhs.448:
  %t1453 = load i32, ptr %slot624, !dbg !818
  %t1454 = icmp ugt i32 %t1453, 244, !dbg !818
  br label %or.end.449, !dbg !818
or.end.449:
  %t1455 = phi i1 [ true, %or.end.447 ], [ %t1454, %or.rhs.448 ], !dbg !818
  br i1 %t1455, label %if.then.450, label %if.else.451, !dbg !818
if.then.450:
  call void @lua_pushvalue(ptr %L, i32 2), !dbg !819
  %t1456 = call i32 @nupp.wrap.u32(double 0x4000000000000000), !dbg !819
  %t1457 = uitofp i32 %t1456 to double, !dbg !819
  call void @lua_pushnumber(ptr %L, double %t1457), !dbg !819
  %t1458 = load i32, ptr %slot615, !dbg !819
  %t1459 = add i32 %t1458, 1, !dbg !819
  %t1460 = uitofp i32 %t1459 to double, !dbg !819
  call void @lua_pushnumber(ptr %L, double %t1460), !dbg !819
  ret i32 3, !dbg !819
if.else.451:
  %t1461 = load i32, ptr %slot624, !dbg !819
  %t1462 = icmp ule i32 %t1461, 223, !dbg !819
  br i1 %t1462, label %if.then.452, label %if.else.453, !dbg !819
if.then.452:
  %t1463 = call i32 @nupp.wrap.u32(double 0x3FF0000000000000), !dbg !820
  store i32 %t1463, ptr %slot43, !dbg !820
  br label %if.end.423, !dbg !820
if.else.453:
  %t1464 = load i32, ptr %slot624, !dbg !820
  %t1465 = icmp ule i32 %t1464, 239, !dbg !820
  br i1 %t1465, label %if.then.454, label %if.else.455, !dbg !820
if.then.454:
  %t1466 = call i32 @nupp.wrap.u32(double 0x4000000000000000), !dbg !821
  store i32 %t1466, ptr %slot43, !dbg !821
  %t1467 = load i32, ptr %slot624, !dbg !822
  %t1468 = icmp eq i32 %t1467, 224, !dbg !822
  br i1 %t1468, label %if.then.457, label %if.else.458, !dbg !822
if.then.457:
  %t1469 = call i32 @nupp.wrap.u32(double 0x3FF0000000000000), !dbg !823
  store i32 %t1469, ptr %slot45, !dbg !823
  br label %if.end.456, !dbg !823
if.else.458:
  %t1470 = load i32, ptr %slot624, !dbg !823
  %t1471 = icmp eq i32 %t1470, 237, !dbg !823
  br i1 %t1471, label %if.then.459, label %if.else.460, !dbg !823
if.then.459:
  %t1472 = call i32 @nupp.wrap.u32(double 0x4000000000000000), !dbg !824
  store i32 %t1472, ptr %slot45, !dbg !824
  br label %if.end.456, !dbg !824
if.else.460:
  br label %if.end.456, !dbg !824
if.end.456:
  br label %if.end.423, !dbg !824
if.else.455:
  %t1473 = call i32 @nupp.wrap.u32(double 0x4008000000000000), !dbg !825
  store i32 %t1473, ptr %slot43, !dbg !825
  %t1474 = load i32, ptr %slot624, !dbg !826
  %t1475 = icmp eq i32 %t1474, 240, !dbg !826
  br i1 %t1475, label %if.then.462, label %if.else.463, !dbg !826
if.then.462:
  %t1476 = call i32 @nupp.wrap.u32(double 0x4008000000000000), !dbg !827
  store i32 %t1476, ptr %slot45, !dbg !827
  br label %if.end.461, !dbg !827
if.else.463:
  %t1477 = load i32, ptr %slot624, !dbg !827
  %t1478 = icmp eq i32 %t1477, 244, !dbg !827
  br i1 %t1478, label %if.then.464, label %if.else.465, !dbg !827
if.then.464:
  %t1479 = call i32 @nupp.wrap.u32(double 0x4010000000000000), !dbg !828
  store i32 %t1479, ptr %slot45, !dbg !828
  br label %if.end.461, !dbg !828
if.else.465:
  br label %if.end.461, !dbg !828
if.end.461:
  br label %if.end.423, !dbg !828
if.end.423:
  store i1 true, ptr %slot46, !dbg !829
  %t1480 = load i32, ptr %slot615, !dbg !830
  store i32 %t1480, ptr %slot48, !dbg !830
  store i1 false, ptr %slot39, !dbg !831
  store i1 false, ptr %slot38, !dbg !832
  br label %if.end.420, !dbg !832
if.else.422:
  %t1481 = load i32, ptr %slot43, !dbg !832
  %t1482 = icmp ne i32 %t1481, 0, !dbg !832
  br i1 %t1482, label %if.then.466, label %if.else.467, !dbg !832
if.then.466:
  call void @lua_pushvalue(ptr %L, i32 2), !dbg !833
  %t1483 = call i32 @nupp.wrap.u32(double 0x4000000000000000), !dbg !833
  %t1484 = uitofp i32 %t1483 to double, !dbg !833
  call void @lua_pushnumber(ptr %L, double %t1484), !dbg !833
  %t1485 = load i32, ptr %slot615, !dbg !833
  %t1486 = add i32 %t1485, 1, !dbg !833
  %t1487 = uitofp i32 %t1486 to double, !dbg !833
  call void @lua_pushnumber(ptr %L, double %t1487), !dbg !833
  ret i32 3, !dbg !833
if.else.467:
  %t1488 = load i32, ptr %slot624, !dbg !833
  %t1489 = icmp eq i32 %t1488, 92, !dbg !833
  br i1 %t1489, label %if.then.468, label %if.else.469, !dbg !833
if.then.468:
  %t1490 = load i1, ptr %slot36, !dbg !834
  %t1491 = xor i1 %t1490, true, !dbg !834
  br i1 %t1491, label %if.then.471, label %if.else.472, !dbg !834
if.then.471:
  call void @lua_pushvalue(ptr %L, i32 2), !dbg !835
  %t1492 = call i32 @nupp.wrap.u32(double 0x4010000000000000), !dbg !835
  %t1493 = uitofp i32 %t1492 to double, !dbg !835
  call void @lua_pushnumber(ptr %L, double %t1493), !dbg !835
  %t1494 = load i32, ptr %slot615, !dbg !835
  %t1495 = add i32 %t1494, 1, !dbg !835
  %t1496 = uitofp i32 %t1495 to double, !dbg !835
  call void @lua_pushnumber(ptr %L, double %t1496), !dbg !835
  ret i32 3, !dbg !835
if.else.472:
  br label %if.end.470, !dbg !835
if.end.470:
  %t1497 = load i1, ptr %slot39, !dbg !836
  br i1 %t1497, label %and.rhs.474, label %and.end.475, !dbg !836
and.rhs.474:
  %t1498 = load i32, ptr %slot615, !dbg !836
  %t1499 = load i32, ptr %slot41, !dbg !836
  %t1500 = add i32 %t1499, 1, !dbg !836
  %t1501 = icmp eq i32 %t1498, %t1500, !dbg !836
  br label %and.end.475, !dbg !836
and.end.475:
  %t1502 = phi i1 [ false, %if.end.470 ], [ %t1501, %and.rhs.474 ], !dbg !836
  br i1 %t1502, label %if.then.476, label %if.else.477, !dbg !836
if.then.476:
  %t1503 = load i1, ptr %slot38, !dbg !837
  %t1504 = xor i1 %t1503, true, !dbg !837
  store i1 %t1504, ptr %slot38, !dbg !837
  br label %if.end.473, !dbg !837
if.else.477:
  store i1 true, ptr %slot38, !dbg !838
  br label %if.end.473, !dbg !838
if.end.473:
  store i1 true, ptr %slot39, !dbg !839
  %t1505 = load i32, ptr %slot615, !dbg !840
  store i32 %t1505, ptr %slot41, !dbg !840
  store i1 true, ptr %slot37, !dbg !841
  br label %if.end.420, !dbg !841
if.else.469:
  %t1506 = load i1, ptr %slot39, !dbg !842
  br i1 %t1506, label %and.rhs.478, label %and.end.479, !dbg !842
and.rhs.478:
  %t1507 = load i32, ptr %slot615, !dbg !842
  %t1508 = load i32, ptr %slot41, !dbg !842
  %t1509 = add i32 %t1508, 1, !dbg !842
  %t1510 = icmp eq i32 %t1507, %t1509, !dbg !842
  br label %and.end.479, !dbg !842
and.end.479:
  %t1511 = phi i1 [ false, %if.else.469 ], [ %t1510, %and.rhs.478 ], !dbg !842
  br i1 %t1511, label %and.rhs.480, label %and.end.481, !dbg !842
and.rhs.480:
  %t1512 = load i1, ptr %slot38, !dbg !842
  br label %and.end.481, !dbg !842
and.end.481:
  %t1513 = phi i1 [ false, %and.end.479 ], [ %t1512, %and.rhs.480 ], !dbg !842
  store i1 %t1513, ptr %slot752, !dbg !842
  %t1514 = load i32, ptr %slot624, !dbg !843
  %t1515 = icmp eq i32 %t1514, 34, !dbg !843
  br i1 %t1515, label %and.rhs.483, label %and.end.484, !dbg !843
and.rhs.483:
  %t1516 = load i1, ptr %slot752, !dbg !843
  %t1517 = xor i1 %t1516, true, !dbg !843
  br label %and.end.484, !dbg !843
and.end.484:
  %t1518 = phi i1 [ false, %and.end.481 ], [ %t1517, %and.rhs.483 ], !dbg !843
  br i1 %t1518, label %if.then.485, label %if.else.486, !dbg !843
if.then.485:
  %t1519 = load i1, ptr %slot36, !dbg !844
  br i1 %t1519, label %if.then.488, label %if.else.489, !dbg !844
if.then.488:
  %t1520 = load i32, ptr %slot615, !dbg !845
  store i32 %t1520, ptr %slot760, !dbg !845
  %t1521 = load i1, ptr %slot37, !dbg !846
  br i1 %t1521, label %if.then.491, label %if.else.492, !dbg !846
if.then.491:
  %t1522 = load i32, ptr %slot615, !dbg !847
  %t1523 = or i32 %t1522, 2147483648, !dbg !847
  store i32 %t1523, ptr %slot760, !dbg !847
  br label %if.end.490, !dbg !847
if.else.492:
  br label %if.end.490, !dbg !847
if.end.490:
  %t1524 = load i32, ptr %slot35, !dbg !848
  %t1525 = load i32, ptr %slot760, !dbg !848
  %t1526 = getelementptr inbounds { ptr, i32, i32, i32, i32, [32 x i32] }, ptr %slot27, i32 0, i32 2, !dbg !848
  %t1527 = load i32, ptr %t1526, !dbg !848
  %t1528 = getelementptr inbounds { ptr, i32, i32, i32, i32, [32 x i32] }, ptr %slot27, i32 0, i32 1, !dbg !848
  %t1529 = load i32, ptr %t1528, !dbg !848
  %t1530 = icmp ugt i32 %t1524, %t1527, !dbg !848
  %t1531 = icmp uge i32 %t1524, %t1529, !dbg !848
  %t1532 = or i1 %t1530, %t1531, !dbg !848
  br i1 %t1532, label %lua.raise.493, label %lua.ok.494, !prof !7, !dbg !848
lua.raise.493:
  %t1533 = getelementptr inbounds ptr, ptr %t1, i64 11, !dbg !848
  %rt.raise.1534 = load ptr, ptr %t1533, !invariant.load !8, !dbg !848
  call void %rt.raise.1534(ptr %L, i64 8) nomerge, !dbg !848
  unreachable, !dbg !848
lua.ok.494:
  %t1535 = icmp eq i32 %t1524, %t1527, !dbg !848
  %t1536 = add i32 %t1527, 1, !dbg !848
  %t1537 = select i1 %t1535, i32 %t1536, i32 %t1527, !dbg !848
  store i32 %t1537, ptr %t1526, !dbg !848
  %t1538 = getelementptr inbounds { ptr, i32, i32, i32, i32, [32 x i32] }, ptr %slot27, i32 0, i32 0, !dbg !848
  %t1539 = load ptr, ptr %t1538, !dbg !848
  %t1540 = zext i32 %t1524 to i64, !dbg !848
  %t1541 = getelementptr inbounds i32, ptr %t1539, i64 %t1540, !dbg !848
  store i32 %t1525, ptr %t1541, !dbg !848
  store i1 false, ptr %slot36, !dbg !849
  br label %if.end.487, !dbg !849
if.else.489:
  %t1542 = load i32, ptr %slot35, !dbg !850
  %t1543 = load i32, ptr %slot615, !dbg !850
  %t1544 = getelementptr inbounds { ptr, i32, i32, i32, i32, [32 x i32] }, ptr %slot27, i32 0, i32 2, !dbg !850
  %t1545 = load i32, ptr %t1544, !dbg !850
  %t1546 = getelementptr inbounds { ptr, i32, i32, i32, i32, [32 x i32] }, ptr %slot27, i32 0, i32 1, !dbg !850
  %t1547 = load i32, ptr %t1546, !dbg !850
  %t1548 = icmp ugt i32 %t1542, %t1545, !dbg !850
  %t1549 = icmp uge i32 %t1542, %t1547, !dbg !850
  %t1550 = or i1 %t1548, %t1549, !dbg !850
  br i1 %t1550, label %lua.raise.495, label %lua.ok.496, !prof !7, !dbg !850
lua.raise.495:
  %t1551 = getelementptr inbounds ptr, ptr %t1, i64 11, !dbg !850
  %rt.raise.1552 = load ptr, ptr %t1551, !invariant.load !8, !dbg !850
  call void %rt.raise.1552(ptr %L, i64 8) nomerge, !dbg !850
  unreachable, !dbg !850
lua.ok.496:
  %t1553 = icmp eq i32 %t1542, %t1545, !dbg !850
  %t1554 = add i32 %t1545, 1, !dbg !850
  %t1555 = select i1 %t1553, i32 %t1554, i32 %t1545, !dbg !850
  store i32 %t1555, ptr %t1544, !dbg !850
  %t1556 = getelementptr inbounds { ptr, i32, i32, i32, i32, [32 x i32] }, ptr %slot27, i32 0, i32 0, !dbg !850
  %t1557 = load ptr, ptr %t1556, !dbg !850
  %t1558 = zext i32 %t1542 to i64, !dbg !850
  %t1559 = getelementptr inbounds i32, ptr %t1557, i64 %t1558, !dbg !850
  store i32 %t1543, ptr %t1559, !dbg !850
  store i1 true, ptr %slot36, !dbg !851
  store i1 false, ptr %slot37, !dbg !852
  br label %if.end.487, !dbg !852
if.end.487:
  %t1560 = load i32, ptr %slot35, !dbg !853
  %t1561 = add i32 %t1560, 1, !dbg !853
  store i32 %t1561, ptr %slot35, !dbg !853
  br label %if.end.482, !dbg !853
if.else.486:
  %t1562 = load i32, ptr %slot624, !dbg !853
  %t1563 = icmp ult i32 %t1562, 32, !dbg !853
  br i1 %t1563, label %if.then.497, label %if.else.498, !dbg !853
if.then.497:
  %t1564 = load i32, ptr %slot624, !dbg !854
  %t1565 = icmp eq i32 %t1564, 9, !dbg !854
  br i1 %t1565, label %or.end.500, label %or.rhs.499, !dbg !854
or.rhs.499:
  %t1566 = load i32, ptr %slot624, !dbg !854
  %t1567 = icmp eq i32 %t1566, 10, !dbg !854
  br label %or.end.500, !dbg !854
or.end.500:
  %t1568 = phi i1 [ true, %if.then.497 ], [ %t1567, %or.rhs.499 ], !dbg !854
  br i1 %t1568, label %or.end.502, label %or.rhs.501, !dbg !854
or.rhs.501:
  %t1569 = load i32, ptr %slot624, !dbg !854
  %t1570 = icmp eq i32 %t1569, 13, !dbg !854
  br label %or.end.502, !dbg !854
or.end.502:
  %t1571 = phi i1 [ true, %or.end.500 ], [ %t1570, %or.rhs.501 ], !dbg !854
  store i1 %t1571, ptr %slot812, !dbg !854
  %t1572 = load i1, ptr %slot36, !dbg !855
  br i1 %t1572, label %or.end.505, label %or.rhs.504, !dbg !855
or.rhs.504:
  %t1573 = load i1, ptr %slot812, !dbg !855
  %t1574 = xor i1 %t1573, true, !dbg !855
  br label %or.end.505, !dbg !855
or.end.505:
  %t1575 = phi i1 [ true, %or.end.502 ], [ %t1574, %or.rhs.504 ], !dbg !855
  br i1 %t1575, label %if.then.506, label %if.else.507, !dbg !855
if.then.506:
  call void @lua_pushvalue(ptr %L, i32 2), !dbg !856
  %t1576 = call i32 @nupp.wrap.u32(double 0x4008000000000000), !dbg !856
  %t1577 = uitofp i32 %t1576 to double, !dbg !856
  call void @lua_pushnumber(ptr %L, double %t1577), !dbg !856
  %t1578 = load i32, ptr %slot615, !dbg !856
  %t1579 = add i32 %t1578, 1, !dbg !856
  %t1580 = uitofp i32 %t1579 to double, !dbg !856
  call void @lua_pushnumber(ptr %L, double %t1580), !dbg !856
  ret i32 3, !dbg !856
if.else.507:
  br label %if.end.503, !dbg !856
if.end.503:
  br label %if.end.482, !dbg !856
if.else.498:
  %t1581 = load i1, ptr %slot36, !dbg !856
  %t1582 = xor i1 %t1581, true, !dbg !856
  br i1 %t1582, label %if.then.508, label %if.else.509, !dbg !856
if.then.508:
  %t1583 = load i32, ptr %slot35, !dbg !857
  %t1584 = load i32, ptr %slot615, !dbg !857
  %t1585 = getelementptr inbounds { ptr, i32, i32, i32, i32, [32 x i32] }, ptr %slot27, i32 0, i32 2, !dbg !857
  %t1586 = load i32, ptr %t1585, !dbg !857
  %t1587 = getelementptr inbounds { ptr, i32, i32, i32, i32, [32 x i32] }, ptr %slot27, i32 0, i32 1, !dbg !857
  %t1588 = load i32, ptr %t1587, !dbg !857
  %t1589 = icmp ugt i32 %t1583, %t1586, !dbg !857
  %t1590 = icmp uge i32 %t1583, %t1588, !dbg !857
  %t1591 = or i1 %t1589, %t1590, !dbg !857
  br i1 %t1591, label %lua.raise.510, label %lua.ok.511, !prof !7, !dbg !857
lua.raise.510:
  %t1592 = getelementptr inbounds ptr, ptr %t1, i64 11, !dbg !857
  %rt.raise.1593 = load ptr, ptr %t1592, !invariant.load !8, !dbg !857
  call void %rt.raise.1593(ptr %L, i64 8) nomerge, !dbg !857
  unreachable, !dbg !857
lua.ok.511:
  %t1594 = icmp eq i32 %t1583, %t1586, !dbg !857
  %t1595 = add i32 %t1586, 1, !dbg !857
  %t1596 = select i1 %t1594, i32 %t1595, i32 %t1586, !dbg !857
  store i32 %t1596, ptr %t1585, !dbg !857
  %t1597 = getelementptr inbounds { ptr, i32, i32, i32, i32, [32 x i32] }, ptr %slot27, i32 0, i32 0, !dbg !857
  %t1598 = load ptr, ptr %t1597, !dbg !857
  %t1599 = zext i32 %t1583 to i64, !dbg !857
  %t1600 = getelementptr inbounds i32, ptr %t1598, i64 %t1599, !dbg !857
  store i32 %t1584, ptr %t1600, !dbg !857
  %t1601 = load i32, ptr %slot35, !dbg !858
  %t1602 = add i32 %t1601, 1, !dbg !858
  store i32 %t1602, ptr %slot35, !dbg !858
  br label %if.end.482, !dbg !858
if.else.509:
  br label %if.end.482, !dbg !858
if.end.482:
  store i1 false, ptr %slot39, !dbg !859
  store i1 false, ptr %slot38, !dbg !860
  br label %if.end.420, !dbg !860
if.end.420:
  br label %if.end.410, !dbg !860
if.else.412:
  br label %if.end.410, !dbg !860
if.end.410:
  br label %while.head.407, !dbg !860
while.end.409:
  %t1603 = load i32, ptr %slot33, !dbg !861
  %t1604 = load i32, ptr %slot70, !dbg !861
  %t1605 = add i32 %t1603, %t1604, !dbg !861
  store i32 %t1605, ptr %slot33, !dbg !861
  br label %while.head.263, !dbg !861
while.end.265:
  br label %cursors.done.13, !dbg !861
cursors.done.13:
  %t1606 = load i32, ptr %slot43, !dbg !862
  %t1607 = icmp ne i32 %t1606, 0, !dbg !862
  br i1 %t1607, label %if.then.513, label %if.else.514, !dbg !862
if.then.513:
  call void @lua_pushvalue(ptr %L, i32 2), !dbg !863
  %t1608 = call i32 @nupp.wrap.u32(double 0x4000000000000000), !dbg !863
  %t1609 = uitofp i32 %t1608 to double, !dbg !863
  call void @lua_pushnumber(ptr %L, double %t1609), !dbg !863
  %t1610 = load i32, ptr %slot48, !dbg !863
  %t1611 = add i32 %t1610, 2, !dbg !863
  %t1612 = uitofp i32 %t1611 to double, !dbg !863
  call void @lua_pushnumber(ptr %L, double %t1612), !dbg !863
  ret i32 3, !dbg !863
if.else.514:
  br label %if.end.512, !dbg !863
if.end.512:
  %t1613 = call i32 @nupp.wrap.u32(double 0x4090000000000000), !dbg !864
  store i32 %t1613, ptr %slot1614, !dbg !864
  %t1615 = load i32, ptr %slot20, !dbg !865
  %t1616 = icmp ule i32 %t1615, 32, !dbg !865
  br i1 %t1616, label %if.then.516, label %if.else.517, !dbg !865
if.then.516:
  %t1617 = call i32 @nupp.wrap.u32(double 0x4030000000000000), !dbg !866
  store i32 %t1617, ptr %slot1614, !dbg !866
  br label %if.end.515, !dbg !866
if.else.517:
  br label %if.end.515, !dbg !866
if.end.515:
  %t1619 = load i32, ptr %slot1614, !dbg !867
  %t1620 = zext i32 %t1619 to i64, !dbg !867
  %t1621 = load i32, ptr %slot20, !dbg !867
  %t1622 = zext i32 %t1621 to i64, !dbg !867
  %t1623 = sext i32 2 to i64, !dbg !867
  %t1624 = sext i32 3 to i64, !dbg !867
  %t1625 = sext i32 4 to i64, !dbg !867
  %t1626 = sext i32 5 to i64, !dbg !867
  %t1627 = sext i32 6 to i64, !dbg !867
  %t1628 = sext i32 7 to i64, !dbg !867
  %t1629 = getelementptr inbounds ptr, ptr %t1, i64 47, !dbg !867
  %rt.builder_init.1630 = load ptr, ptr %t1629, !invariant.load !8, !dbg !867
  call void %rt.builder_init.1630(ptr %L, ptr %slot1618, i64 %t1623, i64 %t1624, i64 %t1625, i64 %t1620, i64 %t1622, i64 %t1626, i64 %t1627, i64 %t1628, i64 0), !dbg !867
  %t1631 = call i32 @nupp.wrap.u32(double 0x0000000000000000), !dbg !868
  store i32 %t1631, ptr %slot1632, !dbg !868
  %t1633 = getelementptr inbounds { ptr, i32, i32, i32, i32, [32 x i32] }, ptr %slot27, i32 0, i32 2, !dbg !869
  %t1634 = load i32, ptr %t1633, !dbg !869
  store i32 %t1634, ptr %slot35, !dbg !869
  %t1635 = call i32 @nupp.wrap.u32(double 0x0000000000000000), !dbg !870
  store i32 %t1635, ptr %slot1636, !dbg !870
  store i1 true, ptr %slot1637, !dbg !871
  store i1 false, ptr %slot1638, !dbg !872
  %t1639 = call i32 @nupp.wrap.u32(double 0x0000000000000000), !dbg !873
  store i32 %t1639, ptr %slot1640, !dbg !873
  br label %while.head.518, !dbg !874
while.head.518:
  %t1641 = load i1, ptr %slot1638, !dbg !874
  %t1642 = xor i1 %t1641, true, !dbg !874
  br i1 %t1642, label %while.body.519, label %while.end.520, !dbg !874
while.body.519:
  store i1 true, ptr %slot1643, !dbg !875
  %t1644 = call i32 @nupp.wrap.u32(double 0x0000000000000000), !dbg !876
  store i32 %t1644, ptr %slot1640, !dbg !876
  br label %while.head.521, !dbg !877
while.head.521:
  %t1645 = load i1, ptr %slot1643, !dbg !877
  br i1 %t1645, label %and.rhs.524, label %and.end.525, !dbg !877
and.rhs.524:
  %t1646 = load i32, ptr %slot1632, !dbg !877
  %t1647 = load i32, ptr %slot20, !dbg !877
  %t1648 = icmp ult i32 %t1646, %t1647, !dbg !877
  br label %and.end.525, !dbg !877
and.end.525:
  %t1649 = phi i1 [ false, %while.head.521 ], [ %t1648, %and.rhs.524 ], !dbg !877
  br i1 %t1649, label %while.body.522, label %while.end.523, !dbg !877
while.body.522:
  %t1650 = load i32, ptr %slot1632, !dbg !878
  %t1651 = zext i32 %t1650 to i64, !dbg !878
  %t1652 = getelementptr inbounds i8, ptr %t14, i64 %t1651, !dbg !878
  %t1653 = load i8, ptr %t1652, !dbg !878
  %t1654 = zext i8 %t1653 to i32, !dbg !878
  store i32 %t1654, ptr %slot1640, !dbg !878
  %t1655 = load i32, ptr %slot1640, !dbg !879
  %t1656 = icmp eq i32 %t1655, 32, !dbg !879
  br i1 %t1656, label %or.end.528, label %or.rhs.527, !dbg !879
or.rhs.527:
  %t1657 = load i32, ptr %slot1640, !dbg !879
  %t1658 = icmp eq i32 %t1657, 9, !dbg !879
  br label %or.end.528, !dbg !879
or.end.528:
  %t1659 = phi i1 [ true, %while.body.522 ], [ %t1658, %or.rhs.527 ], !dbg !879
  br i1 %t1659, label %or.end.530, label %or.rhs.529, !dbg !879
or.rhs.529:
  %t1660 = load i32, ptr %slot1640, !dbg !879
  %t1661 = icmp eq i32 %t1660, 10, !dbg !879
  br label %or.end.530, !dbg !879
or.end.530:
  %t1662 = phi i1 [ true, %or.end.528 ], [ %t1661, %or.rhs.529 ], !dbg !879
  br i1 %t1662, label %or.end.532, label %or.rhs.531, !dbg !879
or.rhs.531:
  %t1663 = load i32, ptr %slot1640, !dbg !879
  %t1664 = icmp eq i32 %t1663, 13, !dbg !879
  br label %or.end.532, !dbg !879
or.end.532:
  %t1665 = phi i1 [ true, %or.end.530 ], [ %t1664, %or.rhs.531 ], !dbg !879
  br i1 %t1665, label %if.then.533, label %if.else.534, !dbg !879
if.then.533:
  %t1666 = load i32, ptr %slot1632, !dbg !880
  %t1667 = add i32 %t1666, 1, !dbg !880
  store i32 %t1667, ptr %slot1632, !dbg !880
  br label %if.end.526, !dbg !880
if.else.534:
  store i1 false, ptr %slot1643, !dbg !881
  br label %if.end.526, !dbg !881
if.end.526:
  br label %while.head.521, !dbg !881
while.end.523:
  %t1668 = load i1, ptr %slot1637, !dbg !882
  br i1 %t1668, label %if.then.536, label %if.else.537, !dbg !882
if.then.536:
  %t1669 = load i32, ptr %slot1632, !dbg !883
  %t1670 = load i32, ptr %slot20, !dbg !883
  %t1671 = icmp uge i32 %t1669, %t1670, !dbg !883
  br i1 %t1671, label %if.then.539, label %if.else.540, !dbg !883
if.then.539:
  call void @lua_pushvalue(ptr %L, i32 2), !dbg !884
  %t1672 = call i32 @nupp.wrap.u32(double 0x3FF0000000000000), !dbg !884
  %t1673 = uitofp i32 %t1672 to double, !dbg !884
  call void @lua_pushnumber(ptr %L, double %t1673), !dbg !884
  %t1674 = load i32, ptr %slot1632, !dbg !884
  %t1675 = add i32 %t1674, 1, !dbg !884
  %t1676 = uitofp i32 %t1675 to double, !dbg !884
  call void @lua_pushnumber(ptr %L, double %t1676), !dbg !884
  ret i32 3, !dbg !884
if.else.540:
  br label %if.end.538, !dbg !884
if.end.538:
  %t1677 = call i32 @nupp.wrap.u32(double 0x0000000000000000), !dbg !885
  store i32 %t1677, ptr %slot1678, !dbg !885
  %t1679 = load i32, ptr %slot1632, !dbg !886
  store i32 %t1679, ptr %slot1680, !dbg !886
  %t1681 = call i32 @nupp.wrap.u32(double 0x0000000000000000), !dbg !887
  store i32 %t1681, ptr %slot1682, !dbg !887
  %t1683 = call i32 @nupp.wrap.u32(double 0x0000000000000000), !dbg !888
  store i32 %t1683, ptr %slot1684, !dbg !888
  %t1685 = call i32 @nupp.wrap.u32(double 0x0000000000000000), !dbg !889
  store i32 %t1685, ptr %slot1686, !dbg !889
  %t1687 = load i32, ptr %slot1640, !dbg !890
  store i32 %t1687, ptr %slot1688, !dbg !890
  %t1689 = load i32, ptr %slot1688, !dbg !891
  %t1690 = icmp eq i32 %t1689, 34, !dbg !891
  br i1 %t1690, label %if.then.542, label %if.else.543, !dbg !891
if.then.542:
  %t1691 = call i32 @nupp.wrap.u32(double 0x4010000000000000), !dbg !892
  store i32 %t1691, ptr %slot1678, !dbg !892
  %t1692 = load i32, ptr %slot1636, !dbg !893
  %t1693 = load i32, ptr %slot35, !dbg !893
  %t1694 = icmp ult i32 %t1692, %t1693, !dbg !893
  br i1 %t1694, label %if.then.545, label %if.else.546, !dbg !893
if.then.545:
  %t1695 = load i32, ptr %slot1636, !dbg !894
  %t1696 = getelementptr inbounds { ptr, i32, i32, i32, i32, [32 x i32] }, ptr %slot27, i32 0, i32 0, !dbg !894
  %t1697 = load ptr, ptr %t1696, !dbg !894
  %t1698 = zext i32 %t1695 to i64, !dbg !894
  %t1699 = getelementptr inbounds i32, ptr %t1697, i64 %t1698, !dbg !894
  %t1700 = load i32, ptr %t1699, !dbg !894
  store i32 %t1700, ptr %slot1701, !dbg !894
  %t1702 = load i32, ptr %slot1701, !dbg !895
  %t1703 = load i32, ptr %slot1632, !dbg !895
  %t1704 = icmp ne i32 %t1702, %t1703, !dbg !895
  br i1 %t1704, label %if.then.548, label %if.else.549, !dbg !895
if.then.548:
  call void @lua_pushvalue(ptr %L, i32 2), !dbg !896
  %t1705 = call i32 @nupp.wrap.u32(double 0x4014000000000000), !dbg !896
  %t1706 = uitofp i32 %t1705 to double, !dbg !896
  call void @lua_pushnumber(ptr %L, double %t1706), !dbg !896
  %t1707 = load i32, ptr %slot1632, !dbg !896
  %t1708 = add i32 %t1707, 1, !dbg !896
  %t1709 = uitofp i32 %t1708 to double, !dbg !896
  call void @lua_pushnumber(ptr %L, double %t1709), !dbg !896
  ret i32 3, !dbg !896
if.else.549:
  br label %if.end.547, !dbg !896
if.end.547:
  %t1710 = load i32, ptr %slot1636, !dbg !897
  %t1711 = add i32 %t1710, 1, !dbg !897
  store i32 %t1711, ptr %slot1636, !dbg !897
  br label %if.end.544, !dbg !897
if.else.546:
  call void @lua_pushvalue(ptr %L, i32 2), !dbg !898
  %t1712 = call i32 @nupp.wrap.u32(double 0x4014000000000000), !dbg !898
  %t1713 = uitofp i32 %t1712 to double, !dbg !898
  call void @lua_pushnumber(ptr %L, double %t1713), !dbg !898
  %t1714 = load i32, ptr %slot1632, !dbg !898
  %t1715 = add i32 %t1714, 1, !dbg !898
  %t1716 = uitofp i32 %t1715 to double, !dbg !898
  call void @lua_pushnumber(ptr %L, double %t1716), !dbg !898
  ret i32 3, !dbg !898
if.end.544:
  %t1717 = load i32, ptr %slot1636, !dbg !899
  %t1718 = load i32, ptr %slot35, !dbg !899
  %t1719 = icmp ult i32 %t1717, %t1718, !dbg !899
  br i1 %t1719, label %if.then.551, label %if.else.552, !dbg !899
if.then.551:
  %t1720 = load i32, ptr %slot1636, !dbg !900
  %t1721 = getelementptr inbounds { ptr, i32, i32, i32, i32, [32 x i32] }, ptr %slot27, i32 0, i32 0, !dbg !900
  %t1722 = load ptr, ptr %t1721, !dbg !900
  %t1723 = zext i32 %t1720 to i64, !dbg !900
  %t1724 = getelementptr inbounds i32, ptr %t1722, i64 %t1723, !dbg !900
  %t1725 = load i32, ptr %t1724, !dbg !900
  store i32 %t1725, ptr %slot1726, !dbg !900
  %t1727 = load i32, ptr %slot1726, !dbg !901
  %t1728 = and i32 %t1727, 2147483647, !dbg !901
  store i32 %t1728, ptr %slot1729, !dbg !901
  %t1730 = load i32, ptr %slot1726, !dbg !902
  %t1731 = and i32 %t1730, 2147483648, !dbg !902
  %t1732 = icmp ne i32 %t1731, 0, !dbg !902
  br i1 %t1732, label %if.then.554, label %if.else.555, !dbg !902
if.then.554:
  %t1733 = call i32 @nupp.wrap.u32(double 0x3FF0000000000000), !dbg !903
  store i32 %t1733, ptr %slot1684, !dbg !903
  br label %if.end.553, !dbg !903
if.else.555:
  br label %if.end.553, !dbg !903
if.end.553:
  %t1734 = load i32, ptr %slot1632, !dbg !904
  %t1735 = add i32 %t1734, 1, !dbg !904
  store i32 %t1735, ptr %slot1680, !dbg !904
  %t1736 = load i32, ptr %slot1729, !dbg !905
  %t1737 = load i32, ptr %slot1680, !dbg !905
  %t1738 = sub i32 %t1736, %t1737, !dbg !905
  store i32 %t1738, ptr %slot1682, !dbg !905
  %t1739 = load i32, ptr %slot1729, !dbg !906
  %t1740 = add i32 %t1739, 1, !dbg !906
  store i32 %t1740, ptr %slot1632, !dbg !906
  %t1741 = load i32, ptr %slot1636, !dbg !907
  %t1742 = add i32 %t1741, 1, !dbg !907
  store i32 %t1742, ptr %slot1636, !dbg !907
  br label %if.end.550, !dbg !907
if.else.552:
  call void @lua_pushvalue(ptr %L, i32 2), !dbg !908
  %t1743 = call i32 @nupp.wrap.u32(double 0x3FF0000000000000), !dbg !908
  %t1744 = uitofp i32 %t1743 to double, !dbg !908
  call void @lua_pushnumber(ptr %L, double %t1744), !dbg !908
  %t1745 = load i32, ptr %slot1632, !dbg !908
  %t1746 = add i32 %t1745, 1, !dbg !908
  %t1747 = uitofp i32 %t1746 to double, !dbg !908
  call void @lua_pushnumber(ptr %L, double %t1747), !dbg !908
  ret i32 3, !dbg !908
if.end.550:
  br label %if.end.541, !dbg !908
if.else.543:
  %t1748 = load i32, ptr %slot1688, !dbg !908
  %t1749 = icmp eq i32 %t1748, 91, !dbg !908
  br i1 %t1749, label %or.end.557, label %or.rhs.556, !dbg !908
or.rhs.556:
  %t1750 = load i32, ptr %slot1688, !dbg !908
  %t1751 = icmp eq i32 %t1750, 123, !dbg !908
  br label %or.end.557, !dbg !908
or.end.557:
  %t1752 = phi i1 [ true, %if.else.543 ], [ %t1751, %or.rhs.556 ], !dbg !908
  br i1 %t1752, label %if.then.558, label %if.else.559, !dbg !908
if.then.558:
  %t1753 = getelementptr inbounds { [10 x i32], i32, i32, i32, i32, i32, i32, ptr, [16 x { i32, i32, i32, i32, i32, i32, i32, i32, i64, i32, i32, i32, i32 }] }, ptr %slot1618, i32 0, i32 1, !dbg !909
  %t1754 = load i32, ptr %t1753, !dbg !909
  %t1755 = load i32, ptr %slot1614, !dbg !909
  %t1756 = icmp uge i32 %t1754, %t1755, !dbg !909
  br i1 %t1756, label %if.then.561, label %if.else.562, !dbg !909
if.then.561:
  call void @lua_pushvalue(ptr %L, i32 2), !dbg !910
  %t1757 = call i32 @nupp.wrap.u32(double 0x3FF0000000000000), !dbg !910
  %t1758 = uitofp i32 %t1757 to double, !dbg !910
  call void @lua_pushnumber(ptr %L, double %t1758), !dbg !910
  %t1759 = load i32, ptr %slot1632, !dbg !910
  %t1760 = add i32 %t1759, 1, !dbg !910
  %t1761 = uitofp i32 %t1760 to double, !dbg !910
  call void @lua_pushnumber(ptr %L, double %t1761), !dbg !910
  ret i32 3, !dbg !910
if.else.562:
  br label %if.end.560, !dbg !910
if.end.560:
  %t1762 = load i32, ptr %slot1688, !dbg !911
  %t1763 = icmp eq i32 %t1762, 91, !dbg !911
  br i1 %t1763, label %if.then.564, label %if.else.565, !dbg !911
if.then.564:
  %t1764 = call i32 @nupp.wrap.u32(double 0x4014000000000000), !dbg !912
  store i32 %t1764, ptr %slot1678, !dbg !912
  br label %if.end.563, !dbg !912
if.else.565:
  %t1765 = call i32 @nupp.wrap.u32(double 0x4018000000000000), !dbg !913
  store i32 %t1765, ptr %slot1678, !dbg !913
  br label %if.end.563, !dbg !913
if.end.563:
  %t1766 = load i32, ptr %slot1632, !dbg !914
  %t1767 = add i32 %t1766, 1, !dbg !914
  store i32 %t1767, ptr %slot1632, !dbg !914
  %t1768 = load i32, ptr %slot1636, !dbg !915
  %t1769 = load i32, ptr %slot35, !dbg !915
  %t1770 = icmp ult i32 %t1768, %t1769, !dbg !915
  br i1 %t1770, label %if.then.567, label %if.else.568, !dbg !915
if.then.567:
  %t1771 = load i32, ptr %slot1688, !dbg !916
  %t1772 = icmp eq i32 %t1771, 123, !dbg !916
  br i1 %t1772, label %if.then.570, label %if.else.571, !dbg !916
if.then.570:
  %t1773 = call i32 @nupp.wrap.u32(double 0x4010000000000000), !dbg !917
  store i32 %t1773, ptr %slot1686, !dbg !917
  br label %if.end.569, !dbg !917
if.else.571:
  %t1774 = getelementptr inbounds { [10 x i32], i32, i32, i32, i32, i32, i32, ptr, [16 x { i32, i32, i32, i32, i32, i32, i32, i32, i64, i32, i32, i32, i32 }] }, ptr %slot1618, i32 0, i32 1, !dbg !917
  %t1775 = load i32, ptr %t1774, !dbg !917
  %t1776 = icmp eq i32 %t1775, 0, !dbg !917
  br i1 %t1776, label %if.then.572, label %if.else.573, !dbg !917
if.then.572:
  %t1777 = load i32, ptr %slot20, !dbg !918
  %t1778 = and i32 5, 31, !dbg !918
  %t1779 = lshr i32 %t1777, %t1778, !dbg !918
  store i32 %t1779, ptr %slot1686, !dbg !918
  %t1780 = load i32, ptr %slot1686, !dbg !919
  %t1781 = icmp ugt i32 %t1780, 262144, !dbg !919
  br i1 %t1781, label %if.then.575, label %if.else.576, !dbg !919
if.then.575:
  %t1782 = call i32 @nupp.wrap.u32(double 0x4110000000000000), !dbg !920
  store i32 %t1782, ptr %slot1686, !dbg !920
  br label %if.end.574, !dbg !920
if.else.576:
  br label %if.end.574, !dbg !920
if.end.574:
  br label %if.end.569, !dbg !920
if.else.573:
  %t1783 = call i32 @nupp.wrap.u32(double 0x4010000000000000), !dbg !921
  store i32 %t1783, ptr %slot1686, !dbg !921
  br label %if.end.569, !dbg !921
if.end.569:
  %t1784 = load i32, ptr %slot1636, !dbg !922
  %t1785 = add i32 %t1784, 1, !dbg !922
  store i32 %t1785, ptr %slot1636, !dbg !922
  br label %if.end.566, !dbg !922
if.else.568:
  call void @lua_pushvalue(ptr %L, i32 2), !dbg !923
  %t1786 = call i32 @nupp.wrap.u32(double 0x4014000000000000), !dbg !923
  %t1787 = uitofp i32 %t1786 to double, !dbg !923
  call void @lua_pushnumber(ptr %L, double %t1787), !dbg !923
  %t1788 = load i32, ptr %slot1632, !dbg !923
  %t1789 = uitofp i32 %t1788 to double, !dbg !923
  call void @lua_pushnumber(ptr %L, double %t1789), !dbg !923
  ret i32 3, !dbg !923
if.end.566:
  br label %if.end.541, !dbg !923
if.else.559:
  %t1790 = load i32, ptr %slot1688, !dbg !923
  %t1791 = icmp eq i32 %t1790, 116, !dbg !923
  br i1 %t1791, label %if.then.577, label %if.else.578, !dbg !923
if.then.577:
  %t1792 = call i32 @nupp.wrap.u32(double 0x3FF0000000000000), !dbg !924
  store i32 %t1792, ptr %slot1678, !dbg !924
  %t1793 = call i32 @nupp.wrap.u32(double 0x0000000000000000), !dbg !925
  store i32 %t1793, ptr %slot1794, !dbg !925
  br label %while.head.579, !dbg !926
while.head.579:
  %t1795 = load i32, ptr %slot1794, !dbg !926
  %t1796 = icmp ult i32 %t1795, 4, !dbg !926
  br i1 %t1796, label %while.body.580, label %while.end.581, !dbg !926
while.body.580:
  %t1797 = load i32, ptr %slot1632, !dbg !927
  %t1798 = load i32, ptr %slot1794, !dbg !927
  %t1799 = add i32 %t1797, %t1798, !dbg !927
  store i32 %t1799, ptr %slot1800, !dbg !927
  %t1801 = load i32, ptr %slot1800, !dbg !928
  %t1802 = load i32, ptr %slot20, !dbg !928
  %t1803 = icmp ult i32 %t1801, %t1802, !dbg !928
  br i1 %t1803, label %if.then.583, label %if.else.584, !dbg !928
if.then.583:
  %t1804 = load i32, ptr %slot1800, !dbg !929
  %t1805 = zext i32 %t1804 to i64, !dbg !929
  %t1806 = getelementptr inbounds i8, ptr %t14, i64 %t1805, !dbg !929
  %t1807 = load i8, ptr %t1806, !dbg !929
  %t1808 = zext i8 %t1807 to i32, !dbg !929
  store i32 %t1808, ptr %slot1809, !dbg !929
  %t1810 = load i32, ptr %slot1794, !dbg !930
  store i32 %t1810, ptr %slot1811, !dbg !930
  store i32 0, ptr %slot1812, !dbg !931
  %t1813 = load i32, ptr %slot1811, !dbg !932
  %t1814 = icmp eq i32 %t1813, 0, !dbg !932
  br i1 %t1814, label %if.then.586, label %if.else.587, !dbg !932
if.then.586:
  %t1815 = call i32 @nupp.wrap.u32(double 0x405D000000000000), !dbg !933
  store i32 %t1815, ptr %slot1812, !dbg !933
  br label %if.end.585, !dbg !933
if.else.587:
  %t1816 = load i32, ptr %slot1811, !dbg !933
  %t1817 = icmp eq i32 %t1816, 1, !dbg !933
  br i1 %t1817, label %if.then.588, label %if.else.589, !dbg !933
if.then.588:
  %t1818 = call i32 @nupp.wrap.u32(double 0x405C800000000000), !dbg !934
  store i32 %t1818, ptr %slot1812, !dbg !934
  br label %if.end.585, !dbg !934
if.else.589:
  %t1819 = load i32, ptr %slot1811, !dbg !934
  %t1820 = icmp eq i32 %t1819, 2, !dbg !934
  br i1 %t1820, label %if.then.590, label %if.else.591, !dbg !934
if.then.590:
  %t1821 = call i32 @nupp.wrap.u32(double 0x405D400000000000), !dbg !935
  store i32 %t1821, ptr %slot1812, !dbg !935
  br label %if.end.585, !dbg !935
if.else.591:
  %t1822 = call i32 @nupp.wrap.u32(double 0x4059400000000000), !dbg !936
  store i32 %t1822, ptr %slot1812, !dbg !936
  br label %if.end.585, !dbg !936
if.end.585:
  %t1823 = load i32, ptr %slot1809, !dbg !937
  %t1824 = load i32, ptr %slot1812, !dbg !937
  %t1825 = icmp ne i32 %t1823, %t1824, !dbg !937
  br i1 %t1825, label %if.then.593, label %if.else.594, !dbg !937
if.then.593:
  call void @lua_pushvalue(ptr %L, i32 2), !dbg !938
  %t1826 = call i32 @nupp.wrap.u32(double 0x3FF0000000000000), !dbg !938
  %t1827 = uitofp i32 %t1826 to double, !dbg !938
  call void @lua_pushnumber(ptr %L, double %t1827), !dbg !938
  %t1828 = load i32, ptr %slot1800, !dbg !938
  %t1829 = add i32 %t1828, 1, !dbg !938
  %t1830 = uitofp i32 %t1829 to double, !dbg !938
  call void @lua_pushnumber(ptr %L, double %t1830), !dbg !938
  ret i32 3, !dbg !938
if.else.594:
  br label %if.end.592, !dbg !938
if.end.592:
  br label %if.end.582, !dbg !938
if.else.584:
  call void @lua_pushvalue(ptr %L, i32 2), !dbg !939
  %t1831 = call i32 @nupp.wrap.u32(double 0x3FF0000000000000), !dbg !939
  %t1832 = uitofp i32 %t1831 to double, !dbg !939
  call void @lua_pushnumber(ptr %L, double %t1832), !dbg !939
  %t1833 = load i32, ptr %slot1800, !dbg !939
  %t1834 = add i32 %t1833, 1, !dbg !939
  %t1835 = uitofp i32 %t1834 to double, !dbg !939
  call void @lua_pushnumber(ptr %L, double %t1835), !dbg !939
  ret i32 3, !dbg !939
if.end.582:
  %t1836 = load i32, ptr %slot1794, !dbg !940
  %t1837 = add i32 %t1836, 1, !dbg !940
  store i32 %t1837, ptr %slot1794, !dbg !940
  br label %while.head.579, !dbg !940
while.end.581:
  %t1838 = call i32 @nupp.wrap.u32(double 0x4010000000000000), !dbg !941
  store i32 %t1838, ptr %slot1682, !dbg !941
  %t1839 = load i32, ptr %slot1632, !dbg !942
  %t1840 = add i32 %t1839, 4, !dbg !942
  store i32 %t1840, ptr %slot1632, !dbg !942
  br label %if.end.541, !dbg !942
if.else.578:
  %t1841 = load i32, ptr %slot1688, !dbg !942
  %t1842 = icmp eq i32 %t1841, 102, !dbg !942
  br i1 %t1842, label %if.then.595, label %if.else.596, !dbg !942
if.then.595:
  %t1843 = call i32 @nupp.wrap.u32(double 0x4000000000000000), !dbg !943
  store i32 %t1843, ptr %slot1678, !dbg !943
  %t1844 = call i32 @nupp.wrap.u32(double 0x0000000000000000), !dbg !944
  store i32 %t1844, ptr %slot1845, !dbg !944
  br label %while.head.597, !dbg !945
while.head.597:
  %t1846 = load i32, ptr %slot1845, !dbg !945
  %t1847 = icmp ult i32 %t1846, 5, !dbg !945
  br i1 %t1847, label %while.body.598, label %while.end.599, !dbg !945
while.body.598:
  %t1848 = load i32, ptr %slot1632, !dbg !946
  %t1849 = load i32, ptr %slot1845, !dbg !946
  %t1850 = add i32 %t1848, %t1849, !dbg !946
  store i32 %t1850, ptr %slot1851, !dbg !946
  %t1852 = load i32, ptr %slot1851, !dbg !947
  %t1853 = load i32, ptr %slot20, !dbg !947
  %t1854 = icmp ult i32 %t1852, %t1853, !dbg !947
  br i1 %t1854, label %if.then.601, label %if.else.602, !dbg !947
if.then.601:
  %t1855 = load i32, ptr %slot1851, !dbg !948
  %t1856 = zext i32 %t1855 to i64, !dbg !948
  %t1857 = getelementptr inbounds i8, ptr %t14, i64 %t1856, !dbg !948
  %t1858 = load i8, ptr %t1857, !dbg !948
  %t1859 = zext i8 %t1858 to i32, !dbg !948
  store i32 %t1859, ptr %slot1860, !dbg !948
  %t1861 = load i32, ptr %slot1845, !dbg !949
  store i32 %t1861, ptr %slot1862, !dbg !949
  store i32 0, ptr %slot1863, !dbg !950
  %t1864 = load i32, ptr %slot1862, !dbg !951
  %t1865 = icmp eq i32 %t1864, 0, !dbg !951
  br i1 %t1865, label %if.then.604, label %if.else.605, !dbg !951
if.then.604:
  %t1866 = call i32 @nupp.wrap.u32(double 0x4059800000000000), !dbg !952
  store i32 %t1866, ptr %slot1863, !dbg !952
  br label %if.end.603, !dbg !952
if.else.605:
  %t1867 = load i32, ptr %slot1862, !dbg !952
  %t1868 = icmp eq i32 %t1867, 1, !dbg !952
  br i1 %t1868, label %if.then.606, label %if.else.607, !dbg !952
if.then.606:
  %t1869 = call i32 @nupp.wrap.u32(double 0x4058400000000000), !dbg !953
  store i32 %t1869, ptr %slot1863, !dbg !953
  br label %if.end.603, !dbg !953
if.else.607:
  %t1870 = load i32, ptr %slot1862, !dbg !953
  %t1871 = icmp eq i32 %t1870, 2, !dbg !953
  br i1 %t1871, label %if.then.608, label %if.else.609, !dbg !953
if.then.608:
  %t1872 = call i32 @nupp.wrap.u32(double 0x405B000000000000), !dbg !954
  store i32 %t1872, ptr %slot1863, !dbg !954
  br label %if.end.603, !dbg !954
if.else.609:
  %t1873 = load i32, ptr %slot1862, !dbg !954
  %t1874 = icmp eq i32 %t1873, 3, !dbg !954
  br i1 %t1874, label %if.then.610, label %if.else.611, !dbg !954
if.then.610:
  %t1875 = call i32 @nupp.wrap.u32(double 0x405CC00000000000), !dbg !955
  store i32 %t1875, ptr %slot1863, !dbg !955
  br label %if.end.603, !dbg !955
if.else.611:
  %t1876 = call i32 @nupp.wrap.u32(double 0x4059400000000000), !dbg !956
  store i32 %t1876, ptr %slot1863, !dbg !956
  br label %if.end.603, !dbg !956
if.end.603:
  %t1877 = load i32, ptr %slot1860, !dbg !957
  %t1878 = load i32, ptr %slot1863, !dbg !957
  %t1879 = icmp ne i32 %t1877, %t1878, !dbg !957
  br i1 %t1879, label %if.then.613, label %if.else.614, !dbg !957
if.then.613:
  call void @lua_pushvalue(ptr %L, i32 2), !dbg !958
  %t1880 = call i32 @nupp.wrap.u32(double 0x3FF0000000000000), !dbg !958
  %t1881 = uitofp i32 %t1880 to double, !dbg !958
  call void @lua_pushnumber(ptr %L, double %t1881), !dbg !958
  %t1882 = load i32, ptr %slot1851, !dbg !958
  %t1883 = add i32 %t1882, 1, !dbg !958
  %t1884 = uitofp i32 %t1883 to double, !dbg !958
  call void @lua_pushnumber(ptr %L, double %t1884), !dbg !958
  ret i32 3, !dbg !958
if.else.614:
  br label %if.end.612, !dbg !958
if.end.612:
  br label %if.end.600, !dbg !958
if.else.602:
  call void @lua_pushvalue(ptr %L, i32 2), !dbg !959
  %t1885 = call i32 @nupp.wrap.u32(double 0x3FF0000000000000), !dbg !959
  %t1886 = uitofp i32 %t1885 to double, !dbg !959
  call void @lua_pushnumber(ptr %L, double %t1886), !dbg !959
  %t1887 = load i32, ptr %slot1851, !dbg !959
  %t1888 = add i32 %t1887, 1, !dbg !959
  %t1889 = uitofp i32 %t1888 to double, !dbg !959
  call void @lua_pushnumber(ptr %L, double %t1889), !dbg !959
  ret i32 3, !dbg !959
if.end.600:
  %t1890 = load i32, ptr %slot1845, !dbg !960
  %t1891 = add i32 %t1890, 1, !dbg !960
  store i32 %t1891, ptr %slot1845, !dbg !960
  br label %while.head.597, !dbg !960
while.end.599:
  %t1892 = call i32 @nupp.wrap.u32(double 0x4014000000000000), !dbg !961
  store i32 %t1892, ptr %slot1682, !dbg !961
  %t1893 = load i32, ptr %slot1632, !dbg !962
  %t1894 = add i32 %t1893, 5, !dbg !962
  store i32 %t1894, ptr %slot1632, !dbg !962
  br label %if.end.541, !dbg !962
if.else.596:
  %t1895 = load i32, ptr %slot1688, !dbg !962
  %t1896 = icmp eq i32 %t1895, 110, !dbg !962
  br i1 %t1896, label %if.then.615, label %if.else.616, !dbg !962
if.then.615:
  %t1897 = call i32 @nupp.wrap.u32(double 0x0000000000000000), !dbg !963
  store i32 %t1897, ptr %slot1678, !dbg !963
  %t1898 = call i32 @nupp.wrap.u32(double 0x0000000000000000), !dbg !964
  store i32 %t1898, ptr %slot1899, !dbg !964
  br label %while.head.617, !dbg !965
while.head.617:
  %t1900 = load i32, ptr %slot1899, !dbg !965
  %t1901 = icmp ult i32 %t1900, 4, !dbg !965
  br i1 %t1901, label %while.body.618, label %while.end.619, !dbg !965
while.body.618:
  %t1902 = load i32, ptr %slot1632, !dbg !966
  %t1903 = load i32, ptr %slot1899, !dbg !966
  %t1904 = add i32 %t1902, %t1903, !dbg !966
  store i32 %t1904, ptr %slot1905, !dbg !966
  %t1906 = load i32, ptr %slot1905, !dbg !967
  %t1907 = load i32, ptr %slot20, !dbg !967
  %t1908 = icmp ult i32 %t1906, %t1907, !dbg !967
  br i1 %t1908, label %if.then.621, label %if.else.622, !dbg !967
if.then.621:
  %t1909 = load i32, ptr %slot1905, !dbg !968
  %t1910 = zext i32 %t1909 to i64, !dbg !968
  %t1911 = getelementptr inbounds i8, ptr %t14, i64 %t1910, !dbg !968
  %t1912 = load i8, ptr %t1911, !dbg !968
  %t1913 = zext i8 %t1912 to i32, !dbg !968
  store i32 %t1913, ptr %slot1914, !dbg !968
  %t1915 = load i32, ptr %slot1899, !dbg !969
  store i32 %t1915, ptr %slot1916, !dbg !969
  store i32 0, ptr %slot1917, !dbg !970
  %t1918 = load i32, ptr %slot1916, !dbg !971
  %t1919 = icmp eq i32 %t1918, 0, !dbg !971
  br i1 %t1919, label %if.then.624, label %if.else.625, !dbg !971
if.then.624:
  %t1920 = call i32 @nupp.wrap.u32(double 0x405B800000000000), !dbg !972
  store i32 %t1920, ptr %slot1917, !dbg !972
  br label %if.end.623, !dbg !972
if.else.625:
  %t1921 = load i32, ptr %slot1916, !dbg !972
  %t1922 = icmp eq i32 %t1921, 1, !dbg !972
  br i1 %t1922, label %if.then.626, label %if.else.627, !dbg !972
if.then.626:
  %t1923 = call i32 @nupp.wrap.u32(double 0x405D400000000000), !dbg !973
  store i32 %t1923, ptr %slot1917, !dbg !973
  br label %if.end.623, !dbg !973
if.else.627:
  %t1924 = call i32 @nupp.wrap.u32(double 0x405B000000000000), !dbg !974
  store i32 %t1924, ptr %slot1917, !dbg !974
  br label %if.end.623, !dbg !974
if.end.623:
  %t1925 = load i32, ptr %slot1914, !dbg !975
  %t1926 = load i32, ptr %slot1917, !dbg !975
  %t1927 = icmp ne i32 %t1925, %t1926, !dbg !975
  br i1 %t1927, label %if.then.629, label %if.else.630, !dbg !975
if.then.629:
  call void @lua_pushvalue(ptr %L, i32 2), !dbg !976
  %t1928 = call i32 @nupp.wrap.u32(double 0x3FF0000000000000), !dbg !976
  %t1929 = uitofp i32 %t1928 to double, !dbg !976
  call void @lua_pushnumber(ptr %L, double %t1929), !dbg !976
  %t1930 = load i32, ptr %slot1905, !dbg !976
  %t1931 = add i32 %t1930, 1, !dbg !976
  %t1932 = uitofp i32 %t1931 to double, !dbg !976
  call void @lua_pushnumber(ptr %L, double %t1932), !dbg !976
  ret i32 3, !dbg !976
if.else.630:
  br label %if.end.628, !dbg !976
if.end.628:
  br label %if.end.620, !dbg !976
if.else.622:
  call void @lua_pushvalue(ptr %L, i32 2), !dbg !977
  %t1933 = call i32 @nupp.wrap.u32(double 0x3FF0000000000000), !dbg !977
  %t1934 = uitofp i32 %t1933 to double, !dbg !977
  call void @lua_pushnumber(ptr %L, double %t1934), !dbg !977
  %t1935 = load i32, ptr %slot1905, !dbg !977
  %t1936 = add i32 %t1935, 1, !dbg !977
  %t1937 = uitofp i32 %t1936 to double, !dbg !977
  call void @lua_pushnumber(ptr %L, double %t1937), !dbg !977
  ret i32 3, !dbg !977
if.end.620:
  %t1938 = load i32, ptr %slot1899, !dbg !978
  %t1939 = add i32 %t1938, 1, !dbg !978
  store i32 %t1939, ptr %slot1899, !dbg !978
  br label %while.head.617, !dbg !978
while.end.619:
  %t1940 = call i32 @nupp.wrap.u32(double 0x4010000000000000), !dbg !979
  store i32 %t1940, ptr %slot1682, !dbg !979
  %t1941 = load i32, ptr %slot1632, !dbg !980
  %t1942 = add i32 %t1941, 4, !dbg !980
  store i32 %t1942, ptr %slot1632, !dbg !980
  br label %if.end.541, !dbg !980
if.else.616:
  %t1943 = load i32, ptr %slot1688, !dbg !980
  %t1944 = icmp eq i32 %t1943, 45, !dbg !980
  br i1 %t1944, label %or.end.632, label %or.rhs.631, !dbg !980
or.rhs.631:
  %t1945 = load i32, ptr %slot1688, !dbg !980
  %t1946 = icmp uge i32 %t1945, 48, !dbg !980
  br i1 %t1946, label %and.rhs.633, label %and.end.634, !dbg !980
and.rhs.633:
  %t1947 = load i32, ptr %slot1688, !dbg !980
  %t1948 = icmp ule i32 %t1947, 57, !dbg !980
  br label %and.end.634, !dbg !980
and.end.634:
  %t1949 = phi i1 [ false, %or.rhs.631 ], [ %t1948, %and.rhs.633 ], !dbg !980
  br label %or.end.632, !dbg !980
or.end.632:
  %t1950 = phi i1 [ true, %if.else.616 ], [ %t1949, %and.end.634 ], !dbg !980
  br i1 %t1950, label %if.then.635, label %if.else.636, !dbg !980
if.then.635:
  %t1951 = call i32 @nupp.wrap.u32(double 0x4008000000000000), !dbg !981
  store i32 %t1951, ptr %slot1678, !dbg !981
  %t1952 = load i32, ptr %slot1632, !dbg !982
  %t1953 = zext i32 %t1952 to i64, !dbg !982
  %t1954 = load i32, ptr %slot20, !dbg !982
  %t1955 = zext i32 %t1954 to i64, !dbg !982
  %t1956 = getelementptr inbounds ptr, ptr %t1, i64 64, !dbg !982
  %rt.builder_number_token.1957 = load ptr, ptr %t1956, !invariant.load !8, !dbg !982
  %t1958 = call i64 %rt.builder_number_token.1957(ptr %L, ptr %slot1618, ptr %t14, i64 %t15, i64 %t1953, i64 %t1955, i64 0), !dbg !982
  %t1959 = trunc i64 %t1958 to i32, !dbg !982
  store i32 %t1959, ptr %slot1960, !dbg !982
  %t1961 = load i32, ptr %slot1960, !dbg !983
  %t1962 = icmp ult i32 %t1961, 2147483648, !dbg !983
  br i1 %t1962, label %if.then.638, label %if.else.639, !dbg !983
if.then.638:
  call void @lua_pushvalue(ptr %L, i32 2), !dbg !984
  %t1963 = call i32 @nupp.wrap.u32(double 0x3FF0000000000000), !dbg !984
  %t1964 = uitofp i32 %t1963 to double, !dbg !984
  call void @lua_pushnumber(ptr %L, double %t1964), !dbg !984
  %t1965 = load i32, ptr %slot1960, !dbg !984
  %t1966 = uitofp i32 %t1965 to double, !dbg !984
  call void @lua_pushnumber(ptr %L, double %t1966), !dbg !984
  ret i32 3, !dbg !984
if.else.639:
  br label %if.end.637, !dbg !984
if.end.637:
  %t1967 = load i32, ptr %slot1960, !dbg !985
  %t1968 = sub i32 %t1967, 2147483648, !dbg !985
  store i32 %t1968, ptr %slot1632, !dbg !985
  %t1969 = load i32, ptr %slot1632, !dbg !986
  %t1970 = load i32, ptr %slot1680, !dbg !986
  %t1971 = sub i32 %t1969, %t1970, !dbg !986
  store i32 %t1971, ptr %slot1682, !dbg !986
  br label %if.end.541, !dbg !986
if.else.636:
  call void @lua_pushvalue(ptr %L, i32 2), !dbg !987
  %t1972 = call i32 @nupp.wrap.u32(double 0x3FF0000000000000), !dbg !987
  %t1973 = uitofp i32 %t1972 to double, !dbg !987
  call void @lua_pushnumber(ptr %L, double %t1973), !dbg !987
  %t1974 = load i32, ptr %slot1632, !dbg !987
  %t1975 = add i32 %t1974, 1, !dbg !987
  %t1976 = uitofp i32 %t1975 to double, !dbg !987
  call void @lua_pushnumber(ptr %L, double %t1976), !dbg !987
  ret i32 3, !dbg !987
if.end.541:
  %t1977 = load i32, ptr %slot1678, !dbg !988
  %t1978 = icmp eq i32 %t1977, 0, !dbg !988
  br i1 %t1978, label %if.then.641, label %if.else.642, !dbg !988
if.then.641:
  %t1979 = getelementptr inbounds ptr, ptr %t1, i64 57, !dbg !989
  %rt.builder_null.1980 = load ptr, ptr %t1979, !invariant.load !8, !dbg !989
  call void %rt.builder_null.1980(ptr %L, ptr %slot1618, i64 0), !dbg !989
  br label %if.end.640, !dbg !989
if.else.642:
  %t1981 = load i32, ptr %slot1678, !dbg !989
  %t1982 = icmp eq i32 %t1981, 1, !dbg !989
  br i1 %t1982, label %if.then.643, label %if.else.644, !dbg !989
if.then.643:
  %t1983 = zext i1 true to i64, !dbg !990
  %t1984 = getelementptr inbounds ptr, ptr %t1, i64 56, !dbg !990
  %rt.builder_boolean.1985 = load ptr, ptr %t1984, !invariant.load !8, !dbg !990
  call void %rt.builder_boolean.1985(ptr %L, ptr %slot1618, i64 %t1983, i64 0), !dbg !990
  br label %if.end.640, !dbg !990
if.else.644:
  %t1986 = load i32, ptr %slot1678, !dbg !990
  %t1987 = icmp eq i32 %t1986, 2, !dbg !990
  br i1 %t1987, label %if.then.645, label %if.else.646, !dbg !990
if.then.645:
  %t1988 = zext i1 false to i64, !dbg !991
  %t1989 = getelementptr inbounds ptr, ptr %t1, i64 56, !dbg !991
  %rt.builder_boolean.1990 = load ptr, ptr %t1989, !invariant.load !8, !dbg !991
  call void %rt.builder_boolean.1990(ptr %L, ptr %slot1618, i64 %t1988, i64 0), !dbg !991
  br label %if.end.640, !dbg !991
if.else.646:
  %t1991 = load i32, ptr %slot1678, !dbg !991
  %t1992 = icmp eq i32 %t1991, 4, !dbg !991
  br i1 %t1992, label %if.then.647, label %if.else.648, !dbg !991
if.then.647:
  %t1993 = load i32, ptr %slot1680, !dbg !992
  %t1994 = zext i32 %t1993 to i64, !dbg !992
  %t1995 = load i32, ptr %slot1682, !dbg !992
  %t1996 = zext i32 %t1995 to i64, !dbg !992
  %t1997 = load i32, ptr %slot1684, !dbg !992
  %t1998 = icmp eq i32 %t1997, 1, !dbg !992
  %t1999 = zext i1 %t1998 to i64, !dbg !992
  %t2000 = getelementptr inbounds ptr, ptr %t1, i64 49, !dbg !992
  %rt.builder_string.2001 = load ptr, ptr %t2000, !invariant.load !8, !dbg !992
  call void %rt.builder_string.2001(ptr %L, ptr %slot1618, ptr %t14, i64 %t15, i64 %t1994, i64 %t1996, i64 %t1999, i64 0, i64 0), !dbg !992
  br label %if.end.640, !dbg !992
if.else.648:
  %t2002 = load i32, ptr %slot1678, !dbg !992
  %t2003 = icmp eq i32 %t2002, 5, !dbg !992
  br i1 %t2003, label %if.then.649, label %if.else.650, !dbg !992
if.then.649:
  %t2004 = load i32, ptr %slot1686, !dbg !993
  %t2005 = zext i32 %t2004 to i64, !dbg !993
  %t2006 = getelementptr inbounds ptr, ptr %t1, i64 48, !dbg !993
  %rt.builder_open.2007 = load ptr, ptr %t2006, !invariant.load !8, !dbg !993
  call void %rt.builder_open.2007(ptr %L, ptr %slot1618, i64 5, i64 %t2005, i64 0), !dbg !993
  br label %if.end.640, !dbg !993
if.else.650:
  %t2008 = load i32, ptr %slot1678, !dbg !993
  %t2009 = icmp eq i32 %t2008, 6, !dbg !993
  br i1 %t2009, label %if.then.651, label %if.else.652, !dbg !993
if.then.651:
  %t2010 = load i32, ptr %slot1686, !dbg !994
  %t2011 = zext i32 %t2010 to i64, !dbg !994
  %t2012 = getelementptr inbounds ptr, ptr %t1, i64 48, !dbg !994
  %rt.builder_open.2013 = load ptr, ptr %t2012, !invariant.load !8, !dbg !994
  call void %rt.builder_open.2013(ptr %L, ptr %slot1618, i64 6, i64 %t2011, i64 0), !dbg !994
  br label %if.end.640, !dbg !994
if.else.652:
  br label %if.end.640, !dbg !994
if.end.640:
  store i1 false, ptr %slot1637, !dbg !995
  br label %if.end.535, !dbg !995
if.else.537:
  %t2014 = getelementptr inbounds { [10 x i32], i32, i32, i32, i32, i32, i32, ptr, [16 x { i32, i32, i32, i32, i32, i32, i32, i32, i64, i32, i32, i32, i32 }] }, ptr %slot1618, i32 0, i32 1, !dbg !995
  %t2015 = load i32, ptr %t2014, !dbg !995
  %t2016 = icmp eq i32 %t2015, 0, !dbg !995
  br i1 %t2016, label %if.then.653, label %if.else.654, !dbg !995
if.then.653:
  %t2017 = load i32, ptr %slot1632, !dbg !996
  %t2018 = load i32, ptr %slot20, !dbg !996
  %t2019 = icmp ult i32 %t2017, %t2018, !dbg !996
  br i1 %t2019, label %if.then.656, label %if.else.657, !dbg !996
if.then.656:
  call void @lua_pushvalue(ptr %L, i32 2), !dbg !997
  %t2020 = call i32 @nupp.wrap.u32(double 0x3FF0000000000000), !dbg !997
  %t2021 = uitofp i32 %t2020 to double, !dbg !997
  call void @lua_pushnumber(ptr %L, double %t2021), !dbg !997
  %t2022 = load i32, ptr %slot1632, !dbg !997
  %t2023 = add i32 %t2022, 1, !dbg !997
  %t2024 = uitofp i32 %t2023 to double, !dbg !997
  call void @lua_pushnumber(ptr %L, double %t2024), !dbg !997
  ret i32 3, !dbg !997
if.else.657:
  br label %if.end.655, !dbg !997
if.end.655:
  store i1 true, ptr %slot1638, !dbg !998
  br label %if.end.535, !dbg !998
if.else.654:
  %t2025 = load i32, ptr %slot1632, !dbg !999
  %t2026 = load i32, ptr %slot20, !dbg !999
  %t2027 = icmp uge i32 %t2025, %t2026, !dbg !999
  br i1 %t2027, label %if.then.659, label %if.else.660, !dbg !999
if.then.659:
  call void @lua_pushvalue(ptr %L, i32 2), !dbg !1000
  %t2028 = call i32 @nupp.wrap.u32(double 0x3FF0000000000000), !dbg !1000
  %t2029 = uitofp i32 %t2028 to double, !dbg !1000
  call void @lua_pushnumber(ptr %L, double %t2029), !dbg !1000
  %t2030 = load i32, ptr %slot1632, !dbg !1000
  %t2031 = add i32 %t2030, 1, !dbg !1000
  %t2032 = uitofp i32 %t2031 to double, !dbg !1000
  call void @lua_pushnumber(ptr %L, double %t2032), !dbg !1000
  ret i32 3, !dbg !1000
if.else.660:
  br label %if.end.658, !dbg !1000
if.end.658:
  %t2033 = getelementptr inbounds { [10 x i32], i32, i32, i32, i32, i32, i32, ptr, [16 x { i32, i32, i32, i32, i32, i32, i32, i32, i64, i32, i32, i32, i32 }] }, ptr %slot1618, i32 0, i32 1, !dbg !1001
  %t2034 = load i32, ptr %t2033, !dbg !1001
  %t2035 = icmp eq i32 %t2034, 0, !dbg !1001
  store i32 0, ptr %slot2036, !dbg !1001
  br i1 %t2035, label %lua.state.662, label %lua.frame.661, !dbg !1001
lua.frame.661:
  %t2037 = getelementptr inbounds { [10 x i32], i32, i32, i32, i32, i32, i32, ptr, [16 x { i32, i32, i32, i32, i32, i32, i32, i32, i64, i32, i32, i32, i32 }] }, ptr %slot1618, i32 0, i32 7, !dbg !1001
  %t2038 = load ptr, ptr %t2037, !dbg !1001
  %t2039 = getelementptr inbounds { [10 x i32], i32, i32, i32, i32, i32, i32, ptr, [16 x { i32, i32, i32, i32, i32, i32, i32, i32, i64, i32, i32, i32, i32 }] }, ptr %slot1618, i32 0, i32 8, !dbg !1001
  %t2040 = icmp eq ptr %t2038, null, !dbg !1001
  %t2041 = select i1 %t2040, ptr %t2039, ptr %t2038, !dbg !1001
  %t2042 = sub i32 %t2034, 1, !dbg !1001
  %t2043 = zext i32 %t2042 to i64, !dbg !1001
  %t2044 = getelementptr inbounds { i32, i32, i32, i32, i32, i32, i32, i32, i64, i32, i32, i32, i32 }, ptr %t2041, i64 %t2043, !dbg !1001
  %t2045 = getelementptr inbounds { i32, i32, i32, i32, i32, i32, i32, i32, i64, i32, i32, i32, i32 }, ptr %t2044, i32 0, i32 2, !dbg !1001
  %t2046 = load i32, ptr %t2045, !dbg !1001
  %t2047 = getelementptr inbounds { i32, i32, i32, i32, i32, i32, i32, i32, i64, i32, i32, i32, i32 }, ptr %t2044, i32 0, i32 4, !dbg !1001
  %t2048 = load i32, ptr %t2047, !dbg !1001
  %t2049 = icmp ne i32 %t2048, 0, !dbg !1001
  %t2050 = select i1 %t2049, i32 256, i32 0, !dbg !1001
  %t2051 = or i32 %t2046, %t2050, !dbg !1001
  store i32 %t2051, ptr %slot2036, !dbg !1001
  br label %lua.state.662, !dbg !1001
lua.state.662:
  %t2052 = load i32, ptr %slot2036, !dbg !1001
  store i32 %t2052, ptr %slot2053, !dbg !1001
  %t2054 = load i32, ptr %slot1640, !dbg !1002
  store i32 %t2054, ptr %slot2055, !dbg !1002
  %t2056 = load i32, ptr %slot2053, !dbg !1003
  %t2057 = and i32 %t2056, 255, !dbg !1003
  store i32 %t2057, ptr %slot2058, !dbg !1003
  %t2059 = load i32, ptr %slot2053, !dbg !1004
  %t2060 = and i32 %t2059, 256, !dbg !1004
  %t2061 = icmp ne i32 %t2060, 0, !dbg !1004
  store i1 %t2061, ptr %slot2062, !dbg !1004
  %t2063 = load i32, ptr %slot2058, !dbg !1005
  %t2064 = icmp eq i32 %t2063, 5, !dbg !1005
  br i1 %t2064, label %and.rhs.663, label %and.end.664, !dbg !1005
and.rhs.663:
  %t2065 = load i32, ptr %slot2055, !dbg !1005
  %t2066 = icmp eq i32 %t2065, 93, !dbg !1005
  br label %and.end.664, !dbg !1005
and.end.664:
  %t2067 = phi i1 [ false, %lua.state.662 ], [ %t2066, %and.rhs.663 ], !dbg !1005
  br i1 %t2067, label %or.end.666, label %or.rhs.665, !dbg !1005
or.rhs.665:
  %t2068 = load i32, ptr %slot2058, !dbg !1005
  %t2069 = icmp eq i32 %t2068, 6, !dbg !1005
  br i1 %t2069, label %and.rhs.667, label %and.end.668, !dbg !1005
and.rhs.667:
  %t2070 = load i32, ptr %slot2055, !dbg !1005
  %t2071 = icmp eq i32 %t2070, 125, !dbg !1005
  br label %and.end.668, !dbg !1005
and.end.668:
  %t2072 = phi i1 [ false, %or.rhs.665 ], [ %t2071, %and.rhs.667 ], !dbg !1005
  br label %or.end.666, !dbg !1005
or.end.666:
  %t2073 = phi i1 [ true, %and.end.664 ], [ %t2072, %and.end.668 ], !dbg !1005
  store i1 %t2073, ptr %slot2074, !dbg !1005
  %t2075 = load i1, ptr %slot2074, !dbg !1006
  br i1 %t2075, label %if.then.670, label %if.else.671, !dbg !1006
if.then.670:
  %t2076 = load i32, ptr %slot1636, !dbg !1007
  %t2077 = load i32, ptr %slot35, !dbg !1007
  %t2078 = icmp uge i32 %t2076, %t2077, !dbg !1007
  br i1 %t2078, label %or.end.674, label %or.rhs.673, !dbg !1007
or.rhs.673:
  %t2079 = load i32, ptr %slot1636, !dbg !1007
  %t2080 = getelementptr inbounds { ptr, i32, i32, i32, i32, [32 x i32] }, ptr %slot27, i32 0, i32 0, !dbg !1007
  %t2081 = load ptr, ptr %t2080, !dbg !1007
  %t2082 = zext i32 %t2079 to i64, !dbg !1007
  %t2083 = getelementptr inbounds i32, ptr %t2081, i64 %t2082, !dbg !1007
  %t2084 = load i32, ptr %t2083, !dbg !1007
  %t2085 = load i32, ptr %slot1632, !dbg !1007
  %t2086 = icmp ne i32 %t2084, %t2085, !dbg !1007
  br label %or.end.674, !dbg !1007
or.end.674:
  %t2087 = phi i1 [ true, %if.then.670 ], [ %t2086, %or.rhs.673 ], !dbg !1007
  br i1 %t2087, label %if.then.675, label %if.else.676, !dbg !1007
if.then.675:
  call void @lua_pushvalue(ptr %L, i32 2), !dbg !1008
  %t2088 = call i32 @nupp.wrap.u32(double 0x4014000000000000), !dbg !1008
  %t2089 = uitofp i32 %t2088 to double, !dbg !1008
  call void @lua_pushnumber(ptr %L, double %t2089), !dbg !1008
  %t2090 = load i32, ptr %slot1632, !dbg !1008
  %t2091 = add i32 %t2090, 1, !dbg !1008
  %t2092 = uitofp i32 %t2091 to double, !dbg !1008
  call void @lua_pushnumber(ptr %L, double %t2092), !dbg !1008
  ret i32 3, !dbg !1008
if.else.676:
  br label %if.end.672, !dbg !1008
if.end.672:
  %t2093 = load i32, ptr %slot1636, !dbg !1009
  %t2094 = add i32 %t2093, 1, !dbg !1009
  store i32 %t2094, ptr %slot1636, !dbg !1009
  %t2095 = load i32, ptr %slot1632, !dbg !1010
  %t2096 = add i32 %t2095, 1, !dbg !1010
  store i32 %t2096, ptr %slot1632, !dbg !1010
  %t2097 = getelementptr inbounds ptr, ptr %t1, i64 58, !dbg !1011
  %rt.builder_close.2098 = load ptr, ptr %t2097, !invariant.load !8, !dbg !1011
  call void %rt.builder_close.2098(ptr %L, ptr %slot1618, i64 0), !dbg !1011
  br label %if.end.669, !dbg !1011
if.else.671:
  %t2099 = load i32, ptr %slot2058, !dbg !1011
  %t2100 = icmp eq i32 %t2099, 5, !dbg !1011
  br i1 %t2100, label %if.then.677, label %if.else.678, !dbg !1011
if.then.677:
  %t2101 = load i1, ptr %slot2062, !dbg !1012
  %t2102 = xor i1 %t2101, true, !dbg !1012
  br i1 %t2102, label %if.then.680, label %if.else.681, !dbg !1012
if.then.680:
  store i1 true, ptr %slot1637, !dbg !1013
  br label %if.end.679, !dbg !1013
if.else.681:
  %t2103 = load i32, ptr %slot2055, !dbg !1013
  %t2104 = icmp eq i32 %t2103, 44, !dbg !1013
  br i1 %t2104, label %if.then.682, label %if.else.683, !dbg !1013
if.then.682:
  %t2105 = load i32, ptr %slot1632, !dbg !1014
  %t2106 = add i32 %t2105, 1, !dbg !1014
  store i32 %t2106, ptr %slot1632, !dbg !1014
  %t2107 = load i32, ptr %slot1636, !dbg !1015
  %t2108 = load i32, ptr %slot35, !dbg !1015
  %t2109 = icmp uge i32 %t2107, %t2108, !dbg !1015
  br i1 %t2109, label %if.then.685, label %if.else.686, !dbg !1015
if.then.685:
  call void @lua_pushvalue(ptr %L, i32 2), !dbg !1016
  %t2110 = call i32 @nupp.wrap.u32(double 0x4014000000000000), !dbg !1016
  %t2111 = uitofp i32 %t2110 to double, !dbg !1016
  call void @lua_pushnumber(ptr %L, double %t2111), !dbg !1016
  %t2112 = load i32, ptr %slot1632, !dbg !1016
  %t2113 = uitofp i32 %t2112 to double, !dbg !1016
  call void @lua_pushnumber(ptr %L, double %t2113), !dbg !1016
  ret i32 3, !dbg !1016
if.else.686:
  br label %if.end.684, !dbg !1016
if.end.684:
  %t2114 = load i32, ptr %slot1636, !dbg !1017
  %t2115 = add i32 %t2114, 1, !dbg !1017
  store i32 %t2115, ptr %slot1636, !dbg !1017
  store i1 true, ptr %slot1637, !dbg !1018
  br label %if.end.679, !dbg !1018
if.else.683:
  call void @lua_pushvalue(ptr %L, i32 2), !dbg !1019
  %t2116 = call i32 @nupp.wrap.u32(double 0x3FF0000000000000), !dbg !1019
  %t2117 = uitofp i32 %t2116 to double, !dbg !1019
  call void @lua_pushnumber(ptr %L, double %t2117), !dbg !1019
  %t2118 = load i32, ptr %slot1632, !dbg !1019
  %t2119 = add i32 %t2118, 1, !dbg !1019
  %t2120 = uitofp i32 %t2119 to double, !dbg !1019
  call void @lua_pushnumber(ptr %L, double %t2120), !dbg !1019
  ret i32 3, !dbg !1019
if.end.679:
  br label %if.end.669, !dbg !1019
if.else.678:
  %t2121 = load i1, ptr %slot2062, !dbg !1020
  br i1 %t2121, label %if.then.688, label %if.else.689, !dbg !1020
if.then.688:
  %t2122 = load i32, ptr %slot2055, !dbg !1021
  %t2123 = icmp ne i32 %t2122, 44, !dbg !1021
  br i1 %t2123, label %if.then.691, label %if.else.692, !dbg !1021
if.then.691:
  call void @lua_pushvalue(ptr %L, i32 2), !dbg !1022
  %t2124 = call i32 @nupp.wrap.u32(double 0x3FF0000000000000), !dbg !1022
  %t2125 = uitofp i32 %t2124 to double, !dbg !1022
  call void @lua_pushnumber(ptr %L, double %t2125), !dbg !1022
  %t2126 = load i32, ptr %slot1632, !dbg !1022
  %t2127 = add i32 %t2126, 1, !dbg !1022
  %t2128 = uitofp i32 %t2127 to double, !dbg !1022
  call void @lua_pushnumber(ptr %L, double %t2128), !dbg !1022
  ret i32 3, !dbg !1022
if.else.692:
  br label %if.end.690, !dbg !1022
if.end.690:
  %t2129 = load i32, ptr %slot1632, !dbg !1023
  %t2130 = add i32 %t2129, 1, !dbg !1023
  store i32 %t2130, ptr %slot1632, !dbg !1023
  %t2131 = load i32, ptr %slot1636, !dbg !1024
  %t2132 = load i32, ptr %slot35, !dbg !1024
  %t2133 = icmp uge i32 %t2131, %t2132, !dbg !1024
  br i1 %t2133, label %if.then.694, label %if.else.695, !dbg !1024
if.then.694:
  call void @lua_pushvalue(ptr %L, i32 2), !dbg !1025
  %t2134 = call i32 @nupp.wrap.u32(double 0x4014000000000000), !dbg !1025
  %t2135 = uitofp i32 %t2134 to double, !dbg !1025
  call void @lua_pushnumber(ptr %L, double %t2135), !dbg !1025
  %t2136 = load i32, ptr %slot1632, !dbg !1025
  %t2137 = uitofp i32 %t2136 to double, !dbg !1025
  call void @lua_pushnumber(ptr %L, double %t2137), !dbg !1025
  ret i32 3, !dbg !1025
if.else.695:
  br label %if.end.693, !dbg !1025
if.end.693:
  %t2138 = load i32, ptr %slot1636, !dbg !1026
  %t2139 = add i32 %t2138, 1, !dbg !1026
  store i32 %t2139, ptr %slot1636, !dbg !1026
  store i1 true, ptr %slot2140, !dbg !1027
  br label %while.head.696, !dbg !1028
while.head.696:
  %t2141 = load i1, ptr %slot2140, !dbg !1028
  br i1 %t2141, label %and.rhs.699, label %and.end.700, !dbg !1028
and.rhs.699:
  %t2142 = load i32, ptr %slot1632, !dbg !1028
  %t2143 = load i32, ptr %slot20, !dbg !1028
  %t2144 = icmp ult i32 %t2142, %t2143, !dbg !1028
  br label %and.end.700, !dbg !1028
and.end.700:
  %t2145 = phi i1 [ false, %while.head.696 ], [ %t2144, %and.rhs.699 ], !dbg !1028
  br i1 %t2145, label %while.body.697, label %while.end.698, !dbg !1028
while.body.697:
  %t2146 = load i32, ptr %slot1632, !dbg !1029
  %t2147 = zext i32 %t2146 to i64, !dbg !1029
  %t2148 = getelementptr inbounds i8, ptr %t14, i64 %t2147, !dbg !1029
  %t2149 = load i8, ptr %t2148, !dbg !1029
  %t2150 = zext i8 %t2149 to i32, !dbg !1029
  store i32 %t2150, ptr %slot2151, !dbg !1029
  %t2152 = load i32, ptr %slot2151, !dbg !1030
  %t2153 = icmp eq i32 %t2152, 32, !dbg !1030
  br i1 %t2153, label %or.end.703, label %or.rhs.702, !dbg !1030
or.rhs.702:
  %t2154 = load i32, ptr %slot2151, !dbg !1030
  %t2155 = icmp eq i32 %t2154, 9, !dbg !1030
  br label %or.end.703, !dbg !1030
or.end.703:
  %t2156 = phi i1 [ true, %while.body.697 ], [ %t2155, %or.rhs.702 ], !dbg !1030
  br i1 %t2156, label %or.end.705, label %or.rhs.704, !dbg !1030
or.rhs.704:
  %t2157 = load i32, ptr %slot2151, !dbg !1030
  %t2158 = icmp eq i32 %t2157, 10, !dbg !1030
  br label %or.end.705, !dbg !1030
or.end.705:
  %t2159 = phi i1 [ true, %or.end.703 ], [ %t2158, %or.rhs.704 ], !dbg !1030
  br i1 %t2159, label %or.end.707, label %or.rhs.706, !dbg !1030
or.rhs.706:
  %t2160 = load i32, ptr %slot2151, !dbg !1030
  %t2161 = icmp eq i32 %t2160, 13, !dbg !1030
  br label %or.end.707, !dbg !1030
or.end.707:
  %t2162 = phi i1 [ true, %or.end.705 ], [ %t2161, %or.rhs.706 ], !dbg !1030
  br i1 %t2162, label %if.then.708, label %if.else.709, !dbg !1030
if.then.708:
  %t2163 = load i32, ptr %slot1632, !dbg !1031
  %t2164 = add i32 %t2163, 1, !dbg !1031
  store i32 %t2164, ptr %slot1632, !dbg !1031
  br label %if.end.701, !dbg !1031
if.else.709:
  store i1 false, ptr %slot2140, !dbg !1032
  br label %if.end.701, !dbg !1032
if.end.701:
  br label %while.head.696, !dbg !1032
while.end.698:
  br label %if.end.687, !dbg !1032
if.else.689:
  br label %if.end.687, !dbg !1032
if.end.687:
  %t2165 = load i32, ptr %slot1632, !dbg !1033
  %t2166 = load i32, ptr %slot20, !dbg !1033
  %t2167 = icmp uge i32 %t2165, %t2166, !dbg !1033
  br i1 %t2167, label %or.end.712, label %or.rhs.711, !dbg !1033
or.rhs.711:
  %t2168 = load i32, ptr %slot1632, !dbg !1033
  %t2169 = zext i32 %t2168 to i64, !dbg !1033
  %t2170 = icmp uge i64 %t2169, %t15, !dbg !1033
  br i1 %t2170, label %lua.raise.713, label %lua.ok.714, !prof !7, !dbg !1033
lua.raise.713:
  %t2171 = getelementptr inbounds ptr, ptr %t1, i64 11, !dbg !1033
  %rt.raise.2172 = load ptr, ptr %t2171, !invariant.load !8, !dbg !1033
  call void %rt.raise.2172(ptr %L, i64 3) nomerge, !dbg !1033
  unreachable, !dbg !1033
lua.ok.714:
  %t2173 = getelementptr inbounds i8, ptr %t14, i64 %t2169, !dbg !1033
  %t2174 = load i8, ptr %t2173, !dbg !1033
  %t2175 = zext i8 %t2174 to i32, !dbg !1033
  %t2176 = icmp ne i32 %t2175, 34, !dbg !1033
  br label %or.end.712, !dbg !1033
or.end.712:
  %t2177 = phi i1 [ true, %if.end.687 ], [ %t2176, %lua.ok.714 ], !dbg !1033
  br i1 %t2177, label %if.then.715, label %if.else.716, !dbg !1033
if.then.715:
  call void @lua_pushvalue(ptr %L, i32 2), !dbg !1034
  %t2178 = call i32 @nupp.wrap.u32(double 0x3FF0000000000000), !dbg !1034
  %t2179 = uitofp i32 %t2178 to double, !dbg !1034
  call void @lua_pushnumber(ptr %L, double %t2179), !dbg !1034
  %t2180 = load i32, ptr %slot1632, !dbg !1034
  %t2181 = add i32 %t2180, 1, !dbg !1034
  %t2182 = uitofp i32 %t2181 to double, !dbg !1034
  call void @lua_pushnumber(ptr %L, double %t2182), !dbg !1034
  ret i32 3, !dbg !1034
if.else.716:
  br label %if.end.710, !dbg !1034
if.end.710:
  %t2183 = load i32, ptr %slot1632, !dbg !1035
  store i32 %t2183, ptr %slot2184, !dbg !1035
  %t2185 = load i32, ptr %slot1636, !dbg !1036
  %t2186 = load i32, ptr %slot35, !dbg !1036
  %t2187 = icmp uge i32 %t2185, %t2186, !dbg !1036
  br i1 %t2187, label %or.end.719, label %or.rhs.718, !dbg !1036
or.rhs.718:
  %t2188 = load i32, ptr %slot1636, !dbg !1036
  %t2189 = getelementptr inbounds { ptr, i32, i32, i32, i32, [32 x i32] }, ptr %slot27, i32 0, i32 0, !dbg !1036
  %t2190 = load ptr, ptr %t2189, !dbg !1036
  %t2191 = zext i32 %t2188 to i64, !dbg !1036
  %t2192 = getelementptr inbounds i32, ptr %t2190, i64 %t2191, !dbg !1036
  %t2193 = load i32, ptr %t2192, !dbg !1036
  %t2194 = load i32, ptr %slot2184, !dbg !1036
  %t2195 = icmp ne i32 %t2193, %t2194, !dbg !1036
  br label %or.end.719, !dbg !1036
or.end.719:
  %t2196 = phi i1 [ true, %if.end.710 ], [ %t2195, %or.rhs.718 ], !dbg !1036
  br i1 %t2196, label %if.then.720, label %if.else.721, !dbg !1036
if.then.720:
  call void @lua_pushvalue(ptr %L, i32 2), !dbg !1037
  %t2197 = call i32 @nupp.wrap.u32(double 0x4014000000000000), !dbg !1037
  %t2198 = uitofp i32 %t2197 to double, !dbg !1037
  call void @lua_pushnumber(ptr %L, double %t2198), !dbg !1037
  %t2199 = load i32, ptr %slot1632, !dbg !1037
  %t2200 = add i32 %t2199, 1, !dbg !1037
  %t2201 = uitofp i32 %t2200 to double, !dbg !1037
  call void @lua_pushnumber(ptr %L, double %t2201), !dbg !1037
  ret i32 3, !dbg !1037
if.else.721:
  br label %if.end.717, !dbg !1037
if.end.717:
  %t2202 = load i32, ptr %slot1636, !dbg !1038
  %t2203 = add i32 %t2202, 1, !dbg !1038
  store i32 %t2203, ptr %slot1636, !dbg !1038
  %t2204 = load i32, ptr %slot1636, !dbg !1039
  %t2205 = load i32, ptr %slot35, !dbg !1039
  %t2206 = icmp uge i32 %t2204, %t2205, !dbg !1039
  br i1 %t2206, label %if.then.723, label %if.else.724, !dbg !1039
if.then.723:
  call void @lua_pushvalue(ptr %L, i32 2), !dbg !1040
  %t2207 = call i32 @nupp.wrap.u32(double 0x3FF0000000000000), !dbg !1040
  %t2208 = uitofp i32 %t2207 to double, !dbg !1040
  call void @lua_pushnumber(ptr %L, double %t2208), !dbg !1040
  %t2209 = load i32, ptr %slot1632, !dbg !1040
  %t2210 = add i32 %t2209, 1, !dbg !1040
  %t2211 = uitofp i32 %t2210 to double, !dbg !1040
  call void @lua_pushnumber(ptr %L, double %t2211), !dbg !1040
  ret i32 3, !dbg !1040
if.else.724:
  br label %if.end.722, !dbg !1040
if.end.722:
  %t2212 = load i32, ptr %slot1636, !dbg !1041
  %t2213 = getelementptr inbounds { ptr, i32, i32, i32, i32, [32 x i32] }, ptr %slot27, i32 0, i32 2, !dbg !1041
  %t2214 = load i32, ptr %t2213, !dbg !1041
  %t2215 = icmp uge i32 %t2212, %t2214, !dbg !1041
  br i1 %t2215, label %lua.raise.725, label %lua.ok.726, !prof !7, !dbg !1041
lua.raise.725:
  %t2216 = getelementptr inbounds ptr, ptr %t1, i64 11, !dbg !1041
  %rt.raise.2217 = load ptr, ptr %t2216, !invariant.load !8, !dbg !1041
  call void %rt.raise.2217(ptr %L, i64 7) nomerge, !dbg !1041
  unreachable, !dbg !1041
lua.ok.726:
  %t2218 = getelementptr inbounds { ptr, i32, i32, i32, i32, [32 x i32] }, ptr %slot27, i32 0, i32 0, !dbg !1041
  %t2219 = load ptr, ptr %t2218, !dbg !1041
  %t2220 = zext i32 %t2212 to i64, !dbg !1041
  %t2221 = getelementptr inbounds i32, ptr %t2219, i64 %t2220, !dbg !1041
  %t2222 = load i32, ptr %t2221, !dbg !1041
  store i32 %t2222, ptr %slot2223, !dbg !1041
  %t2224 = load i32, ptr %slot2223, !dbg !1042
  %t2225 = and i32 %t2224, 2147483647, !dbg !1042
  store i32 %t2225, ptr %slot2226, !dbg !1042
  %t2227 = load i32, ptr %slot2223, !dbg !1043
  %t2228 = and i32 %t2227, 2147483648, !dbg !1043
  %t2229 = icmp ne i32 %t2228, 0, !dbg !1043
  store i1 %t2229, ptr %slot2230, !dbg !1043
  %t2231 = load i32, ptr %slot1636, !dbg !1044
  %t2232 = add i32 %t2231, 1, !dbg !1044
  store i32 %t2232, ptr %slot1636, !dbg !1044
  %t2233 = load i32, ptr %slot2184, !dbg !1045
  %t2234 = add i32 %t2233, 1, !dbg !1045
  store i32 %t2234, ptr %slot2235, !dbg !1045
  %t2236 = load i32, ptr %slot2226, !dbg !1046
  %t2237 = load i32, ptr %slot2235, !dbg !1046
  %t2238 = sub i32 %t2236, %t2237, !dbg !1046
  store i32 %t2238, ptr %slot2239, !dbg !1046
  %t2240 = load i32, ptr %slot2235, !dbg !1047
  %t2241 = zext i32 %t2240 to i64, !dbg !1047
  %t2242 = load i32, ptr %slot2239, !dbg !1047
  %t2243 = zext i32 %t2242 to i64, !dbg !1047
  %t2244 = load i1, ptr %slot2230, !dbg !1047
  %t2245 = zext i1 %t2244 to i64, !dbg !1047
  %t2246 = getelementptr inbounds ptr, ptr %t1, i64 49, !dbg !1047
  %rt.builder_string.2247 = load ptr, ptr %t2246, !invariant.load !8, !dbg !1047
  call void %rt.builder_string.2247(ptr %L, ptr %slot1618, ptr %t14, i64 %t15, i64 %t2241, i64 %t2243, i64 %t2245, i64 1, i64 0), !dbg !1047
  %t2248 = load i32, ptr %slot2226, !dbg !1048
  %t2249 = add i32 %t2248, 1, !dbg !1048
  store i32 %t2249, ptr %slot1632, !dbg !1048
  store i1 true, ptr %slot2250, !dbg !1049
  br label %while.head.727, !dbg !1050
while.head.727:
  %t2251 = load i1, ptr %slot2250, !dbg !1050
  br i1 %t2251, label %and.rhs.730, label %and.end.731, !dbg !1050
and.rhs.730:
  %t2252 = load i32, ptr %slot1632, !dbg !1050
  %t2253 = load i32, ptr %slot20, !dbg !1050
  %t2254 = icmp ult i32 %t2252, %t2253, !dbg !1050
  br label %and.end.731, !dbg !1050
and.end.731:
  %t2255 = phi i1 [ false, %while.head.727 ], [ %t2254, %and.rhs.730 ], !dbg !1050
  br i1 %t2255, label %while.body.728, label %while.end.729, !dbg !1050
while.body.728:
  %t2256 = load i32, ptr %slot1632, !dbg !1051
  %t2257 = zext i32 %t2256 to i64, !dbg !1051
  %t2258 = getelementptr inbounds i8, ptr %t14, i64 %t2257, !dbg !1051
  %t2259 = load i8, ptr %t2258, !dbg !1051
  %t2260 = zext i8 %t2259 to i32, !dbg !1051
  store i32 %t2260, ptr %slot2261, !dbg !1051
  %t2262 = load i32, ptr %slot2261, !dbg !1052
  %t2263 = icmp eq i32 %t2262, 32, !dbg !1052
  br i1 %t2263, label %or.end.734, label %or.rhs.733, !dbg !1052
or.rhs.733:
  %t2264 = load i32, ptr %slot2261, !dbg !1052
  %t2265 = icmp eq i32 %t2264, 9, !dbg !1052
  br label %or.end.734, !dbg !1052
or.end.734:
  %t2266 = phi i1 [ true, %while.body.728 ], [ %t2265, %or.rhs.733 ], !dbg !1052
  br i1 %t2266, label %or.end.736, label %or.rhs.735, !dbg !1052
or.rhs.735:
  %t2267 = load i32, ptr %slot2261, !dbg !1052
  %t2268 = icmp eq i32 %t2267, 10, !dbg !1052
  br label %or.end.736, !dbg !1052
or.end.736:
  %t2269 = phi i1 [ true, %or.end.734 ], [ %t2268, %or.rhs.735 ], !dbg !1052
  br i1 %t2269, label %or.end.738, label %or.rhs.737, !dbg !1052
or.rhs.737:
  %t2270 = load i32, ptr %slot2261, !dbg !1052
  %t2271 = icmp eq i32 %t2270, 13, !dbg !1052
  br label %or.end.738, !dbg !1052
or.end.738:
  %t2272 = phi i1 [ true, %or.end.736 ], [ %t2271, %or.rhs.737 ], !dbg !1052
  br i1 %t2272, label %if.then.739, label %if.else.740, !dbg !1052
if.then.739:
  %t2273 = load i32, ptr %slot1632, !dbg !1053
  %t2274 = add i32 %t2273, 1, !dbg !1053
  store i32 %t2274, ptr %slot1632, !dbg !1053
  br label %if.end.732, !dbg !1053
if.else.740:
  store i1 false, ptr %slot2250, !dbg !1054
  br label %if.end.732, !dbg !1054
if.end.732:
  br label %while.head.727, !dbg !1054
while.end.729:
  %t2275 = load i32, ptr %slot1632, !dbg !1055
  %t2276 = load i32, ptr %slot20, !dbg !1055
  %t2277 = icmp uge i32 %t2275, %t2276, !dbg !1055
  br i1 %t2277, label %or.end.743, label %or.rhs.742, !dbg !1055
or.rhs.742:
  %t2278 = load i32, ptr %slot1632, !dbg !1055
  %t2279 = zext i32 %t2278 to i64, !dbg !1055
  %t2280 = icmp uge i64 %t2279, %t15, !dbg !1055
  br i1 %t2280, label %lua.raise.744, label %lua.ok.745, !prof !7, !dbg !1055
lua.raise.744:
  %t2281 = getelementptr inbounds ptr, ptr %t1, i64 11, !dbg !1055
  %rt.raise.2282 = load ptr, ptr %t2281, !invariant.load !8, !dbg !1055
  call void %rt.raise.2282(ptr %L, i64 3) nomerge, !dbg !1055
  unreachable, !dbg !1055
lua.ok.745:
  %t2283 = getelementptr inbounds i8, ptr %t14, i64 %t2279, !dbg !1055
  %t2284 = load i8, ptr %t2283, !dbg !1055
  %t2285 = zext i8 %t2284 to i32, !dbg !1055
  %t2286 = icmp ne i32 %t2285, 58, !dbg !1055
  br label %or.end.743, !dbg !1055
or.end.743:
  %t2287 = phi i1 [ true, %while.end.729 ], [ %t2286, %lua.ok.745 ], !dbg !1055
  br i1 %t2287, label %if.then.746, label %if.else.747, !dbg !1055
if.then.746:
  call void @lua_pushvalue(ptr %L, i32 2), !dbg !1056
  %t2288 = call i32 @nupp.wrap.u32(double 0x3FF0000000000000), !dbg !1056
  %t2289 = uitofp i32 %t2288 to double, !dbg !1056
  call void @lua_pushnumber(ptr %L, double %t2289), !dbg !1056
  %t2290 = load i32, ptr %slot1632, !dbg !1056
  %t2291 = add i32 %t2290, 1, !dbg !1056
  %t2292 = uitofp i32 %t2291 to double, !dbg !1056
  call void @lua_pushnumber(ptr %L, double %t2292), !dbg !1056
  ret i32 3, !dbg !1056
if.else.747:
  br label %if.end.741, !dbg !1056
if.end.741:
  %t2293 = load i32, ptr %slot1636, !dbg !1057
  %t2294 = load i32, ptr %slot35, !dbg !1057
  %t2295 = icmp uge i32 %t2293, %t2294, !dbg !1057
  br i1 %t2295, label %or.end.750, label %or.rhs.749, !dbg !1057
or.rhs.749:
  %t2296 = load i32, ptr %slot1636, !dbg !1057
  %t2297 = getelementptr inbounds { ptr, i32, i32, i32, i32, [32 x i32] }, ptr %slot27, i32 0, i32 0, !dbg !1057
  %t2298 = load ptr, ptr %t2297, !dbg !1057
  %t2299 = zext i32 %t2296 to i64, !dbg !1057
  %t2300 = getelementptr inbounds i32, ptr %t2298, i64 %t2299, !dbg !1057
  %t2301 = load i32, ptr %t2300, !dbg !1057
  %t2302 = load i32, ptr %slot1632, !dbg !1057
  %t2303 = icmp ne i32 %t2301, %t2302, !dbg !1057
  br label %or.end.750, !dbg !1057
or.end.750:
  %t2304 = phi i1 [ true, %if.end.741 ], [ %t2303, %or.rhs.749 ], !dbg !1057
  br i1 %t2304, label %if.then.751, label %if.else.752, !dbg !1057
if.then.751:
  call void @lua_pushvalue(ptr %L, i32 2), !dbg !1058
  %t2305 = call i32 @nupp.wrap.u32(double 0x4014000000000000), !dbg !1058
  %t2306 = uitofp i32 %t2305 to double, !dbg !1058
  call void @lua_pushnumber(ptr %L, double %t2306), !dbg !1058
  %t2307 = load i32, ptr %slot1632, !dbg !1058
  %t2308 = add i32 %t2307, 1, !dbg !1058
  %t2309 = uitofp i32 %t2308 to double, !dbg !1058
  call void @lua_pushnumber(ptr %L, double %t2309), !dbg !1058
  ret i32 3, !dbg !1058
if.else.752:
  br label %if.end.748, !dbg !1058
if.end.748:
  %t2310 = load i32, ptr %slot1632, !dbg !1059
  %t2311 = add i32 %t2310, 1, !dbg !1059
  store i32 %t2311, ptr %slot1632, !dbg !1059
  %t2312 = load i32, ptr %slot1636, !dbg !1060
  %t2313 = add i32 %t2312, 1, !dbg !1060
  store i32 %t2313, ptr %slot1636, !dbg !1060
  store i1 true, ptr %slot1637, !dbg !1061
  br label %if.end.669, !dbg !1061
if.end.669:
  br label %if.end.535, !dbg !1061
if.end.535:
  br label %while.head.518, !dbg !1061
while.end.520:
  %t2314 = getelementptr inbounds ptr, ptr %t1, i64 65, !dbg !1062
  %rt.builder_finish.2315 = load ptr, ptr %t2314, !invariant.load !8, !dbg !1062
  call void %rt.builder_finish.2315(ptr %L, ptr %slot1618), !dbg !1062
  %t2316 = call i32 @nupp.wrap.u32(double 0x0000000000000000), !dbg !1062
  %t2317 = uitofp i32 %t2316 to double, !dbg !1062
  call void @lua_pushnumber(ptr %L, double %t2317), !dbg !1062
  %t2318 = call i32 @nupp.wrap.u32(double 0x0000000000000000), !dbg !1062
  %t2319 = uitofp i32 %t2318 to double, !dbg !1062
  call void @lua_pushnumber(ptr %L, double %t2319), !dbg !1062
  ret i32 3, !dbg !1062
}

define i32 @ks_register_db5c9457e129530e_070172d80baf7574__neon(ptr %L) #0 {
entry:
  %slot6 = alloca i64, align 8
  br label %body
body:
  %t1 = call i32 @lua_checkstack(ptr %L, i32 4)
  %t2 = icmp eq i32 %t1, 0
  br i1 %t2, label %lua.raise.1, label %lua.ok.2, !prof !7
lua.raise.1:
  %t3 = call i32 (ptr, ptr, ...) @luaL_error(ptr %L, ptr @nupp.bytes.1, ptr @nupp.bytes.2) nomerge
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
  call void @lua_getfield(ptr %L, i32 -10002, ptr @nupp.bytes.3)
  call void @lua_pushlstring(ptr %L, ptr @nupp.bytes.4, i64 19)
  call void @lua_call(ptr %L, i32 1, i32 1)
  call void @lua_getfield(ptr %L, i32 -1, ptr @nupp.bytes.5)
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
  %t12 = call i32 (ptr, ptr, ...) @luaL_error(ptr %L, ptr @nupp.bytes.1, ptr @nupp.bytes.6) nomerge
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
  %t68 = call i32 (ptr, ptr, ...) @luaL_error(ptr %L, ptr @nupp.bytes.1, ptr @nupp.bytes.6) nomerge
  unreachable
lua.ok.9:
  store ptr %t13, ptr @ks.rt
  call void @lua_settop(ptr %L, i32 -3)
  call void @lua_createtable(ptr %L, i32 0, i32 3)
  call void @lua_pushlstring(ptr %L, ptr @nupp.bytes.7, i64 40)
  call void @lua_pushcclosure(ptr %L, ptr @ks_db5c9457e129530e___nupp_const_decode_fused_24f677cbe166e03f__5f5f6e757070436f6e73745f6465636f646546757365645f32346636373763626531363665303366__neon_lua, i32 0)
  call void @lua_rawset(ptr %L, i32 -3)
  call void @lua_pushlstring(ptr %L, ptr @nupp.bytes.8, i64 40)
  call void @lua_pushcclosure(ptr %L, ptr @ks_db5c9457e129530e___nupp_const_decode_fused_a640dbc37ebbc1be__5f5f6e757070436f6e73745f6465636f646546757365645f61363430646263333765626263316265__neon_lua, i32 0)
  call void @lua_rawset(ptr %L, i32 -3)
  call void @lua_pushlstring(ptr %L, ptr @nupp.bytes.9, i64 40)
  call void @lua_pushcclosure(ptr %L, ptr @ks_db5c9457e129530e___nupp_const_decode_fused_f007fffb3d50ef9f__5f5f6e757070436f6e73745f6465636f646546757365645f66303037666666623364353065663966__neon_lua, i32 0)
  call void @lua_rawset(ptr %L, i32 -3)
  ret i32 1
}

attributes #0 = { uwtable "probe-stack"="inline-asm" "frame-pointer"="non-leaf" }
attributes #1 = { alwaysinline nounwind uwtable "frame-pointer"="non-leaf" }
attributes #2 = { alwaysinline nounwind }
!llvm.dbg.cu = !{!1}
!llvm.module.flags = !{!2, !3}
!0 = !DIFile(filename: "fused.nupp", directory: "/private/tmp/nupp-codegen-experiment/src/nupp/codec/json/internal/decoder")
!1 = distinct !DICompileUnit(language: DW_LANG_C11, file: !0, producer: "nupp", isOptimized: true, runtimeVersion: 0, emissionKind: LineTablesOnly)
!2 = !{i32 7, !"Dwarf Version", i32 4}
!3 = !{i32 2, !"Debug Info Version", i32 3}
!4 = !DISubroutineType(types: !{})
!5 = distinct !DISubprogram(name: "__nuppConst_decodeFused_24f677cbe166e03f", scope: !0, file: !0, line: 138, type: !4, scopeLine: 138, spFlags: DISPFlagDefinition | DISPFlagOptimized, unit: !1)
!6 = !DILocation(line: 138, column: 1, scope: !5)
!7 = !{!"branch_weights", i32 1, i32 1048575}
!8 = !{}
!9 = !DILocation(line: 138, column: 5, scope: !5)
!10 = !DILocation(line: 139, column: 5, scope: !5)
!11 = !DILocation(line: 140, column: 9, scope: !5)
!12 = !DILocation(line: 143, column: 5, scope: !5)
!13 = !DILocation(line: 144, column: 5, scope: !5)
!14 = !DILocation(line: 145, column: 5, scope: !5)
!15 = !DILocation(line: 146, column: 5, scope: !5)
!16 = !DILocation(line: 147, column: 5, scope: !5)
!17 = !DILocation(line: 152, column: 5, scope: !5)
!18 = !DILocation(line: 153, column: 5, scope: !5)
!19 = !DILocation(line: 154, column: 5, scope: !5)
!20 = !DILocation(line: 159, column: 5, scope: !5)
!21 = !DILocation(line: 160, column: 5, scope: !5)
!22 = !DILocation(line: 161, column: 5, scope: !5)
!23 = !DILocation(line: 162, column: 5, scope: !5)
!24 = !DILocation(line: 163, column: 5, scope: !5)
!25 = !DILocation(line: 166, column: 5, scope: !5)
!26 = !DILocation(line: 167, column: 5, scope: !5)
!27 = !DILocation(line: 171, column: 5, scope: !5)
!28 = !DILocation(line: 178, column: 5, scope: !5)
!29 = !DILocation(line: 179, column: 9, scope: !5)
!30 = !DILocation(line: 180, column: 9, scope: !5)
!31 = !DILocation(line: 181, column: 9, scope: !5)
!32 = !DILocation(line: 182, column: 13, scope: !5)
!33 = !DILocation(line: 184, column: 17, scope: !5)
!34 = !DILocation(line: 185, column: 17, scope: !5)
!35 = !DILocation(line: 186, column: 17, scope: !5)
!36 = !DILocation(line: 187, column: 17, scope: !5)
!37 = !DILocation(line: 188, column: 17, scope: !5)
!38 = !DILocation(line: 189, column: 17, scope: !5)
!39 = !DILocation(line: 190, column: 17, scope: !5)
!40 = !DILocation(line: 191, column: 21, scope: !5)
!41 = !DILocation(line: 192, column: 21, scope: !5)
!42 = !DILocation(line: 194, column: 21, scope: !5)
!43 = !DILocation(line: 198, column: 21, scope: !5)
!44 = !DILocation(line: 199, column: 21, scope: !5)
!45 = !DILocation(line: 200, column: 25, scope: !5)
!46 = !DILocation(line: 201, column: 25, scope: !5)
!47 = !DILocation(line: 204, column: 29, scope: !5)
!48 = !DILocation(line: 211, column: 17, scope: !5)
!49 = !DILocation(line: 218, column: 21, scope: !5)
!50 = !DILocation(line: 219, column: 21, scope: !5)
!51 = !DILocation(line: 220, column: 21, scope: !5)
!52 = !DILocation(line: 221, column: 21, scope: !5)
!53 = !DILocation(line: 230, column: 21, scope: !5)
!54 = !DILocation(line: 231, column: 21, scope: !5)
!55 = !DILocation(line: 232, column: 21, scope: !5)
!56 = !DILocation(line: 251, column: 21, scope: !5)
!57 = !DILocation(line: 252, column: 21, scope: !5)
!58 = !DILocation(line: 260, column: 21, scope: !5)
!59 = !DILocation(line: 261, column: 21, scope: !5)
!60 = !DILocation(line: 269, column: 25, scope: !5)
!61 = !DILocation(line: 274, column: 25, scope: !5)
!62 = !DILocation(line: 277, column: 21, scope: !5)
!63 = !DILocation(line: 279, column: 17, scope: !5)
!64 = !DILocation(line: 280, column: 21, scope: !5)
!65 = !DILocation(line: 282, column: 21, scope: !5)
!66 = !DILocation(line: 286, column: 9, scope: !5)
!67 = !DILocation(line: 292, column: 13, scope: !5)
!68 = !DILocation(line: 293, column: 13, scope: !5)
!69 = !DILocation(line: 294, column: 13, scope: !5)
!70 = !DILocation(line: 295, column: 13, scope: !5)
!71 = !DILocation(line: 296, column: 17, scope: !5)
!72 = !DILocation(line: 297, column: 17, scope: !5)
!73 = !DILocation(line: 298, column: 21, scope: !5)
!74 = !DILocation(line: 303, column: 21, scope: !5)
!75 = !DILocation(line: 304, column: 25, scope: !5)
!76 = !DILocation(line: 306, column: 21, scope: !5)
!77 = !DILocation(line: 307, column: 21, scope: !5)
!78 = !DILocation(line: 308, column: 25, scope: !5)
!79 = !DILocation(line: 310, column: 25, scope: !5)
!80 = !DILocation(line: 312, column: 21, scope: !5)
!81 = !DILocation(line: 313, column: 25, scope: !5)
!82 = !DILocation(line: 314, column: 25, scope: !5)
!83 = !DILocation(line: 315, column: 25, scope: !5)
!84 = !DILocation(line: 318, column: 25, scope: !5)
!85 = !DILocation(line: 319, column: 29, scope: !5)
!86 = !DILocation(line: 320, column: 33, scope: !5)
!87 = !DILocation(line: 322, column: 33, scope: !5)
!88 = !DILocation(line: 324, column: 33, scope: !5)
!89 = !DILocation(line: 326, column: 33, scope: !5)
!90 = !DILocation(line: 330, column: 21, scope: !5)
!91 = !DILocation(line: 332, column: 21, scope: !5)
!92 = !DILocation(line: 339, column: 13, scope: !5)
!93 = !DILocation(line: 340, column: 17, scope: !5)
!94 = !DILocation(line: 341, column: 17, scope: !5)
!95 = !DILocation(line: 352, column: 21, scope: !5)
!96 = !DILocation(line: 355, column: 13, scope: !5)
!97 = !DILocation(line: 358, column: 9, scope: !5)
!98 = !DILocation(line: 359, column: 13, scope: !5)
!99 = !DILocation(line: 360, column: 13, scope: !5)
!100 = !DILocation(line: 361, column: 13, scope: !5)
!101 = !DILocation(line: 362, column: 13, scope: !5)
!102 = !DILocation(line: 363, column: 17, scope: !5)
!103 = !DILocation(line: 367, column: 17, scope: !5)
!104 = !DILocation(line: 368, column: 21, scope: !5)
!105 = !DILocation(line: 370, column: 17, scope: !5)
!106 = !DILocation(line: 371, column: 21, scope: !5)
!107 = !DILocation(line: 372, column: 21, scope: !5)
!108 = !DILocation(line: 373, column: 25, scope: !5)
!109 = !DILocation(line: 374, column: 29, scope: !5)
!110 = !DILocation(line: 376, column: 25, scope: !5)
!111 = !DILocation(line: 380, column: 25, scope: !5)
!112 = !DILocation(line: 381, column: 29, scope: !5)
!113 = !DILocation(line: 383, column: 25, scope: !5)
!114 = !DILocation(line: 384, column: 25, scope: !5)
!115 = !DILocation(line: 386, column: 25, scope: !5)
!116 = !DILocation(line: 388, column: 25, scope: !5)
!117 = !DILocation(line: 390, column: 25, scope: !5)
!118 = !DILocation(line: 391, column: 25, scope: !5)
!119 = !DILocation(line: 392, column: 29, scope: !5)
!120 = !DILocation(line: 394, column: 29, scope: !5)
!121 = !DILocation(line: 397, column: 25, scope: !5)
!122 = !DILocation(line: 398, column: 25, scope: !5)
!123 = !DILocation(line: 399, column: 29, scope: !5)
!124 = !DILocation(line: 401, column: 29, scope: !5)
!125 = !DILocation(line: 404, column: 21, scope: !5)
!126 = !DILocation(line: 405, column: 21, scope: !5)
!127 = !DILocation(line: 406, column: 21, scope: !5)
!128 = !DILocation(line: 407, column: 21, scope: !5)
!129 = !DILocation(line: 410, column: 21, scope: !5)
!130 = !DILocation(line: 412, column: 21, scope: !5)
!131 = !DILocation(line: 413, column: 25, scope: !5)
!132 = !DILocation(line: 415, column: 21, scope: !5)
!133 = !DILocation(line: 416, column: 25, scope: !5)
!134 = !DILocation(line: 418, column: 25, scope: !5)
!135 = !DILocation(line: 420, column: 21, scope: !5)
!136 = !DILocation(line: 421, column: 21, scope: !5)
!137 = !DILocation(line: 422, column: 21, scope: !5)
!138 = !DILocation(line: 424, column: 21, scope: !5)
!139 = !DILocation(line: 425, column: 21, scope: !5)
!140 = !DILocation(line: 429, column: 25, scope: !5)
!141 = !DILocation(line: 430, column: 29, scope: !5)
!142 = !DILocation(line: 431, column: 29, scope: !5)
!143 = !DILocation(line: 432, column: 33, scope: !5)
!144 = !DILocation(line: 434, column: 29, scope: !5)
!145 = !DILocation(line: 435, column: 29, scope: !5)
!146 = !DILocation(line: 437, column: 29, scope: !5)
!147 = !DILocation(line: 438, column: 29, scope: !5)
!148 = !DILocation(line: 439, column: 29, scope: !5)
!149 = !DILocation(line: 441, column: 25, scope: !5)
!150 = !DILocation(line: 443, column: 25, scope: !5)
!151 = !DILocation(line: 444, column: 25, scope: !5)
!152 = !DILocation(line: 445, column: 29, scope: !5)
!153 = !DILocation(line: 450, column: 25, scope: !5)
!154 = !DILocation(line: 451, column: 25, scope: !5)
!155 = !DILocation(line: 453, column: 21, scope: !5)
!156 = !DILocation(line: 454, column: 21, scope: !5)
!157 = !DILocation(line: 459, column: 9, scope: !5)
!158 = !DILocation(line: 462, column: 5, scope: !5)
!159 = !DILocation(line: 465, column: 9, scope: !5)
!160 = !DILocation(line: 468, column: 5, scope: !5)
!161 = !DILocation(line: 469, column: 5, scope: !5)
!162 = !DILocation(line: 470, column: 9, scope: !5)
!163 = !DILocation(line: 472, column: 5, scope: !5)
!164 = !DILocation(line: 495, column: 5, scope: !5)
!165 = !DILocation(line: 496, column: 5, scope: !5)
!166 = !DILocation(line: 497, column: 5, scope: !5)
!167 = !DILocation(line: 498, column: 5, scope: !5)
!168 = !DILocation(line: 499, column: 5, scope: !5)
!169 = !DILocation(line: 505, column: 5, scope: !5)
!170 = !DILocation(line: 506, column: 5, scope: !5)
!171 = !DILocation(line: 507, column: 9, scope: !5)
!172 = !DILocation(line: 508, column: 9, scope: !5)
!173 = !DILocation(line: 509, column: 9, scope: !5)
!174 = !DILocation(line: 510, column: 13, scope: !5)
!175 = !DILocation(line: 511, column: 13, scope: !5)
!176 = !DILocation(line: 512, column: 17, scope: !5)
!177 = !DILocation(line: 514, column: 17, scope: !5)
!178 = !DILocation(line: 518, column: 9, scope: !5)
!179 = !DILocation(line: 519, column: 13, scope: !5)
!180 = !DILocation(line: 520, column: 17, scope: !5)
!181 = !DILocation(line: 523, column: 13, scope: !5)
!182 = !DILocation(line: 524, column: 13, scope: !5)
!183 = !DILocation(line: 525, column: 13, scope: !5)
!184 = !DILocation(line: 526, column: 13, scope: !5)
!185 = !DILocation(line: 527, column: 13, scope: !5)
!186 = !DILocation(line: 528, column: 13, scope: !5)
!187 = !DILocation(line: 530, column: 13, scope: !5)
!188 = !DILocation(line: 531, column: 17, scope: !5)
!189 = !DILocation(line: 532, column: 17, scope: !5)
!190 = !DILocation(line: 533, column: 21, scope: !5)
!191 = !DILocation(line: 534, column: 21, scope: !5)
!192 = !DILocation(line: 535, column: 25, scope: !5)
!193 = !DILocation(line: 537, column: 21, scope: !5)
!194 = !DILocation(line: 539, column: 21, scope: !5)
!195 = !DILocation(line: 541, column: 17, scope: !5)
!196 = !DILocation(line: 542, column: 21, scope: !5)
!197 = !DILocation(line: 543, column: 21, scope: !5)
!198 = !DILocation(line: 544, column: 21, scope: !5)
!199 = !DILocation(line: 545, column: 25, scope: !5)
!200 = !DILocation(line: 547, column: 21, scope: !5)
!201 = !DILocation(line: 548, column: 21, scope: !5)
!202 = !DILocation(line: 552, column: 21, scope: !5)
!203 = !DILocation(line: 553, column: 21, scope: !5)
!204 = !DILocation(line: 555, column: 21, scope: !5)
!205 = !DILocation(line: 558, column: 17, scope: !5)
!206 = !DILocation(line: 559, column: 21, scope: !5)
!207 = !DILocation(line: 561, column: 17, scope: !5)
!208 = !DILocation(line: 562, column: 21, scope: !5)
!209 = !DILocation(line: 564, column: 21, scope: !5)
!210 = !DILocation(line: 566, column: 17, scope: !5)
!211 = !DILocation(line: 567, column: 17, scope: !5)
!212 = !DILocation(line: 568, column: 21, scope: !5)
!213 = !DILocation(line: 571, column: 25, scope: !5)
!214 = !DILocation(line: 577, column: 25, scope: !5)
!215 = !DILocation(line: 578, column: 25, scope: !5)
!216 = !DILocation(line: 579, column: 29, scope: !5)
!217 = !DILocation(line: 582, column: 25, scope: !5)
!218 = !DILocation(line: 584, column: 21, scope: !5)
!219 = !DILocation(line: 586, column: 21, scope: !5)
!220 = !DILocation(line: 589, column: 17, scope: !5)
!221 = !DILocation(line: 590, column: 17, scope: !5)
!222 = !DILocation(line: 591, column: 17, scope: !5)
!223 = !DILocation(line: 592, column: 21, scope: !5)
!224 = !DILocation(line: 593, column: 21, scope: !5)
!225 = !DILocation(line: 594, column: 25, scope: !5)
!226 = !DILocation(line: 595, column: 57, scope: !5)
!227 = !DILocation(line: 595, column: 25, scope: !5)
!228 = !DILocation(line: 595, column: 50, scope: !5)
!229 = !DILocation(line: 596, column: 29, scope: !5)
!230 = !DILocation(line: 597, column: 29, scope: !5)
!231 = !DILocation(line: 598, column: 29, scope: !5)
!232 = !DILocation(line: 599, column: 29, scope: !5)
!233 = !DILocation(line: 601, column: 25, scope: !5)
!234 = !DILocation(line: 602, column: 29, scope: !5)
!235 = !DILocation(line: 605, column: 25, scope: !5)
!236 = !DILocation(line: 607, column: 21, scope: !5)
!237 = !DILocation(line: 609, column: 17, scope: !5)
!238 = !DILocation(line: 610, column: 17, scope: !5)
!239 = !DILocation(line: 612, column: 17, scope: !5)
!240 = !DILocation(line: 613, column: 17, scope: !5)
!241 = !DILocation(line: 614, column: 17, scope: !5)
!242 = !DILocation(line: 615, column: 21, scope: !5)
!243 = !DILocation(line: 616, column: 21, scope: !5)
!244 = !DILocation(line: 617, column: 25, scope: !5)
!245 = !DILocation(line: 618, column: 57, scope: !5)
!246 = !DILocation(line: 618, column: 25, scope: !5)
!247 = !DILocation(line: 618, column: 50, scope: !5)
!248 = !DILocation(line: 619, column: 29, scope: !5)
!249 = !DILocation(line: 620, column: 29, scope: !5)
!250 = !DILocation(line: 621, column: 29, scope: !5)
!251 = !DILocation(line: 622, column: 29, scope: !5)
!252 = !DILocation(line: 623, column: 29, scope: !5)
!253 = !DILocation(line: 625, column: 25, scope: !5)
!254 = !DILocation(line: 626, column: 29, scope: !5)
!255 = !DILocation(line: 629, column: 25, scope: !5)
!256 = !DILocation(line: 631, column: 21, scope: !5)
!257 = !DILocation(line: 633, column: 17, scope: !5)
!258 = !DILocation(line: 634, column: 17, scope: !5)
!259 = !DILocation(line: 636, column: 17, scope: !5)
!260 = !DILocation(line: 637, column: 17, scope: !5)
!261 = !DILocation(line: 638, column: 17, scope: !5)
!262 = !DILocation(line: 639, column: 21, scope: !5)
!263 = !DILocation(line: 640, column: 21, scope: !5)
!264 = !DILocation(line: 641, column: 25, scope: !5)
!265 = !DILocation(line: 642, column: 57, scope: !5)
!266 = !DILocation(line: 642, column: 25, scope: !5)
!267 = !DILocation(line: 642, column: 50, scope: !5)
!268 = !DILocation(line: 643, column: 29, scope: !5)
!269 = !DILocation(line: 644, column: 29, scope: !5)
!270 = !DILocation(line: 645, column: 29, scope: !5)
!271 = !DILocation(line: 647, column: 25, scope: !5)
!272 = !DILocation(line: 648, column: 29, scope: !5)
!273 = !DILocation(line: 651, column: 25, scope: !5)
!274 = !DILocation(line: 653, column: 21, scope: !5)
!275 = !DILocation(line: 655, column: 17, scope: !5)
!276 = !DILocation(line: 656, column: 17, scope: !5)
!277 = !DILocation(line: 658, column: 17, scope: !5)
!278 = !DILocation(line: 659, column: 17, scope: !5)
!279 = !DILocation(line: 660, column: 17, scope: !5)
!280 = !DILocation(line: 661, column: 21, scope: !5)
!281 = !DILocation(line: 663, column: 17, scope: !5)
!282 = !DILocation(line: 664, column: 17, scope: !5)
!283 = !DILocation(line: 666, column: 17, scope: !5)
!284 = !DILocation(line: 669, column: 13, scope: !5)
!285 = !DILocation(line: 670, column: 17, scope: !5)
!286 = !DILocation(line: 672, column: 17, scope: !5)
!287 = !DILocation(line: 674, column: 17, scope: !5)
!288 = !DILocation(line: 676, column: 17, scope: !5)
!289 = !DILocation(line: 678, column: 17, scope: !5)
!290 = !DILocation(line: 680, column: 17, scope: !5)
!291 = !DILocation(line: 682, column: 13, scope: !5)
!292 = !DILocation(line: 684, column: 13, scope: !5)
!293 = !DILocation(line: 685, column: 17, scope: !5)
!294 = !DILocation(line: 687, column: 13, scope: !5)
!295 = !DILocation(line: 689, column: 13, scope: !5)
!296 = !DILocation(line: 690, column: 17, scope: !5)
!297 = !DILocation(line: 692, column: 13, scope: !5)
!298 = !DILocation(line: 693, column: 13, scope: !5)
!299 = !DILocation(line: 694, column: 13, scope: !5)
!300 = !DILocation(line: 695, column: 13, scope: !5)
!301 = !DILocation(line: 696, column: 13, scope: !5)
!302 = !DILocation(line: 697, column: 13, scope: !5)
!303 = !DILocation(line: 698, column: 17, scope: !5)
!304 = !DILocation(line: 699, column: 21, scope: !5)
!305 = !DILocation(line: 701, column: 17, scope: !5)
!306 = !DILocation(line: 702, column: 17, scope: !5)
!307 = !DILocation(line: 703, column: 17, scope: !5)
!308 = !DILocation(line: 705, column: 17, scope: !5)
!309 = !DILocation(line: 706, column: 21, scope: !5)
!310 = !DILocation(line: 708, column: 21, scope: !5)
!311 = !DILocation(line: 709, column: 21, scope: !5)
!312 = !DILocation(line: 710, column: 25, scope: !5)
!313 = !DILocation(line: 712, column: 21, scope: !5)
!314 = !DILocation(line: 713, column: 21, scope: !5)
!315 = !DILocation(line: 715, column: 21, scope: !5)
!316 = !DILocation(line: 718, column: 17, scope: !5)
!317 = !DILocation(line: 719, column: 21, scope: !5)
!318 = !DILocation(line: 720, column: 25, scope: !5)
!319 = !DILocation(line: 722, column: 21, scope: !5)
!320 = !DILocation(line: 723, column: 21, scope: !5)
!321 = !DILocation(line: 724, column: 25, scope: !5)
!322 = !DILocation(line: 726, column: 21, scope: !5)
!323 = !DILocation(line: 727, column: 21, scope: !5)
!324 = !DILocation(line: 728, column: 21, scope: !5)
!325 = !DILocation(line: 729, column: 25, scope: !5)
!326 = !DILocation(line: 730, column: 25, scope: !5)
!327 = !DILocation(line: 731, column: 29, scope: !5)
!328 = !DILocation(line: 733, column: 29, scope: !5)
!329 = !DILocation(line: 737, column: 17, scope: !5)
!330 = !DILocation(line: 738, column: 21, scope: !5)
!331 = !DILocation(line: 740, column: 17, scope: !5)
!332 = !DILocation(line: 741, column: 17, scope: !5)
!333 = !DILocation(line: 742, column: 21, scope: !5)
!334 = !DILocation(line: 744, column: 17, scope: !5)
!335 = !DILocation(line: 745, column: 17, scope: !5)
!336 = !DILocation(line: 746, column: 21, scope: !5)
!337 = !DILocation(line: 748, column: 17, scope: !5)
!338 = !DILocation(line: 749, column: 17, scope: !5)
!339 = !DILocation(line: 750, column: 17, scope: !5)
!340 = !DILocation(line: 751, column: 17, scope: !5)
!341 = !DILocation(line: 752, column: 17, scope: !5)
!342 = !DILocation(line: 753, column: 17, scope: !5)
!343 = !DILocation(line: 754, column: 17, scope: !5)
!344 = !DILocation(line: 755, column: 17, scope: !5)
!345 = !DILocation(line: 756, column: 17, scope: !5)
!346 = !DILocation(line: 757, column: 17, scope: !5)
!347 = !DILocation(line: 758, column: 21, scope: !5)
!348 = !DILocation(line: 759, column: 21, scope: !5)
!349 = !DILocation(line: 760, column: 25, scope: !5)
!350 = !DILocation(line: 762, column: 25, scope: !5)
!351 = !DILocation(line: 765, column: 17, scope: !5)
!352 = !DILocation(line: 766, column: 21, scope: !5)
!353 = !DILocation(line: 768, column: 17, scope: !5)
!354 = !DILocation(line: 769, column: 21, scope: !5)
!355 = !DILocation(line: 771, column: 17, scope: !5)
!356 = !DILocation(line: 772, column: 17, scope: !5)
!357 = !DILocation(line: 773, column: 17, scope: !5)
!358 = !DILocation(line: 778, column: 5, scope: !5)
!359 = distinct !DISubprogram(name: "__nuppConst_decodeFused_a640dbc37ebbc1be", scope: !0, file: !0, line: 138, type: !4, scopeLine: 138, spFlags: DISPFlagDefinition | DISPFlagOptimized, unit: !1)
!360 = !DILocation(line: 138, column: 1, scope: !359)
!361 = !DILocation(line: 138, column: 5, scope: !359)
!362 = !DILocation(line: 139, column: 5, scope: !359)
!363 = !DILocation(line: 140, column: 9, scope: !359)
!364 = !DILocation(line: 143, column: 5, scope: !359)
!365 = !DILocation(line: 144, column: 5, scope: !359)
!366 = !DILocation(line: 145, column: 5, scope: !359)
!367 = !DILocation(line: 146, column: 5, scope: !359)
!368 = !DILocation(line: 147, column: 5, scope: !359)
!369 = !DILocation(line: 152, column: 5, scope: !359)
!370 = !DILocation(line: 153, column: 5, scope: !359)
!371 = !DILocation(line: 154, column: 5, scope: !359)
!372 = !DILocation(line: 159, column: 5, scope: !359)
!373 = !DILocation(line: 160, column: 5, scope: !359)
!374 = !DILocation(line: 161, column: 5, scope: !359)
!375 = !DILocation(line: 162, column: 5, scope: !359)
!376 = !DILocation(line: 163, column: 5, scope: !359)
!377 = !DILocation(line: 166, column: 5, scope: !359)
!378 = !DILocation(line: 167, column: 5, scope: !359)
!379 = !DILocation(line: 171, column: 5, scope: !359)
!380 = !DILocation(line: 178, column: 5, scope: !359)
!381 = !DILocation(line: 179, column: 9, scope: !359)
!382 = !DILocation(line: 180, column: 9, scope: !359)
!383 = !DILocation(line: 181, column: 9, scope: !359)
!384 = !DILocation(line: 182, column: 13, scope: !359)
!385 = !DILocation(line: 184, column: 17, scope: !359)
!386 = !DILocation(line: 185, column: 17, scope: !359)
!387 = !DILocation(line: 186, column: 17, scope: !359)
!388 = !DILocation(line: 187, column: 17, scope: !359)
!389 = !DILocation(line: 188, column: 17, scope: !359)
!390 = !DILocation(line: 189, column: 17, scope: !359)
!391 = !DILocation(line: 190, column: 17, scope: !359)
!392 = !DILocation(line: 191, column: 21, scope: !359)
!393 = !DILocation(line: 192, column: 21, scope: !359)
!394 = !DILocation(line: 194, column: 21, scope: !359)
!395 = !DILocation(line: 198, column: 21, scope: !359)
!396 = !DILocation(line: 199, column: 21, scope: !359)
!397 = !DILocation(line: 200, column: 25, scope: !359)
!398 = !DILocation(line: 201, column: 25, scope: !359)
!399 = !DILocation(line: 204, column: 29, scope: !359)
!400 = !DILocation(line: 211, column: 17, scope: !359)
!401 = !DILocation(line: 218, column: 21, scope: !359)
!402 = !DILocation(line: 219, column: 21, scope: !359)
!403 = !DILocation(line: 220, column: 21, scope: !359)
!404 = !DILocation(line: 221, column: 21, scope: !359)
!405 = !DILocation(line: 230, column: 21, scope: !359)
!406 = !DILocation(line: 231, column: 21, scope: !359)
!407 = !DILocation(line: 232, column: 21, scope: !359)
!408 = !DILocation(line: 251, column: 21, scope: !359)
!409 = !DILocation(line: 252, column: 21, scope: !359)
!410 = !DILocation(line: 260, column: 21, scope: !359)
!411 = !DILocation(line: 261, column: 21, scope: !359)
!412 = !DILocation(line: 269, column: 25, scope: !359)
!413 = !DILocation(line: 274, column: 25, scope: !359)
!414 = !DILocation(line: 277, column: 21, scope: !359)
!415 = !DILocation(line: 279, column: 17, scope: !359)
!416 = !DILocation(line: 280, column: 21, scope: !359)
!417 = !DILocation(line: 282, column: 21, scope: !359)
!418 = !DILocation(line: 286, column: 9, scope: !359)
!419 = !DILocation(line: 292, column: 13, scope: !359)
!420 = !DILocation(line: 293, column: 13, scope: !359)
!421 = !DILocation(line: 294, column: 13, scope: !359)
!422 = !DILocation(line: 295, column: 13, scope: !359)
!423 = !DILocation(line: 296, column: 17, scope: !359)
!424 = !DILocation(line: 297, column: 17, scope: !359)
!425 = !DILocation(line: 298, column: 21, scope: !359)
!426 = !DILocation(line: 303, column: 21, scope: !359)
!427 = !DILocation(line: 304, column: 25, scope: !359)
!428 = !DILocation(line: 306, column: 21, scope: !359)
!429 = !DILocation(line: 307, column: 21, scope: !359)
!430 = !DILocation(line: 308, column: 25, scope: !359)
!431 = !DILocation(line: 310, column: 25, scope: !359)
!432 = !DILocation(line: 312, column: 21, scope: !359)
!433 = !DILocation(line: 313, column: 25, scope: !359)
!434 = !DILocation(line: 314, column: 25, scope: !359)
!435 = !DILocation(line: 315, column: 25, scope: !359)
!436 = !DILocation(line: 318, column: 25, scope: !359)
!437 = !DILocation(line: 319, column: 29, scope: !359)
!438 = !DILocation(line: 320, column: 33, scope: !359)
!439 = !DILocation(line: 322, column: 33, scope: !359)
!440 = !DILocation(line: 324, column: 33, scope: !359)
!441 = !DILocation(line: 326, column: 33, scope: !359)
!442 = !DILocation(line: 330, column: 21, scope: !359)
!443 = !DILocation(line: 332, column: 21, scope: !359)
!444 = !DILocation(line: 339, column: 13, scope: !359)
!445 = !DILocation(line: 340, column: 17, scope: !359)
!446 = !DILocation(line: 341, column: 17, scope: !359)
!447 = !DILocation(line: 352, column: 21, scope: !359)
!448 = !DILocation(line: 355, column: 13, scope: !359)
!449 = !DILocation(line: 358, column: 9, scope: !359)
!450 = !DILocation(line: 359, column: 13, scope: !359)
!451 = !DILocation(line: 360, column: 13, scope: !359)
!452 = !DILocation(line: 361, column: 13, scope: !359)
!453 = !DILocation(line: 362, column: 13, scope: !359)
!454 = !DILocation(line: 363, column: 17, scope: !359)
!455 = !DILocation(line: 367, column: 17, scope: !359)
!456 = !DILocation(line: 368, column: 21, scope: !359)
!457 = !DILocation(line: 370, column: 17, scope: !359)
!458 = !DILocation(line: 371, column: 21, scope: !359)
!459 = !DILocation(line: 372, column: 21, scope: !359)
!460 = !DILocation(line: 373, column: 25, scope: !359)
!461 = !DILocation(line: 374, column: 29, scope: !359)
!462 = !DILocation(line: 376, column: 25, scope: !359)
!463 = !DILocation(line: 380, column: 25, scope: !359)
!464 = !DILocation(line: 381, column: 29, scope: !359)
!465 = !DILocation(line: 383, column: 25, scope: !359)
!466 = !DILocation(line: 384, column: 25, scope: !359)
!467 = !DILocation(line: 386, column: 25, scope: !359)
!468 = !DILocation(line: 388, column: 25, scope: !359)
!469 = !DILocation(line: 390, column: 25, scope: !359)
!470 = !DILocation(line: 391, column: 25, scope: !359)
!471 = !DILocation(line: 392, column: 29, scope: !359)
!472 = !DILocation(line: 394, column: 29, scope: !359)
!473 = !DILocation(line: 397, column: 25, scope: !359)
!474 = !DILocation(line: 398, column: 25, scope: !359)
!475 = !DILocation(line: 399, column: 29, scope: !359)
!476 = !DILocation(line: 401, column: 29, scope: !359)
!477 = !DILocation(line: 404, column: 21, scope: !359)
!478 = !DILocation(line: 405, column: 21, scope: !359)
!479 = !DILocation(line: 406, column: 21, scope: !359)
!480 = !DILocation(line: 407, column: 21, scope: !359)
!481 = !DILocation(line: 410, column: 21, scope: !359)
!482 = !DILocation(line: 412, column: 21, scope: !359)
!483 = !DILocation(line: 413, column: 25, scope: !359)
!484 = !DILocation(line: 415, column: 21, scope: !359)
!485 = !DILocation(line: 416, column: 25, scope: !359)
!486 = !DILocation(line: 418, column: 25, scope: !359)
!487 = !DILocation(line: 420, column: 21, scope: !359)
!488 = !DILocation(line: 421, column: 21, scope: !359)
!489 = !DILocation(line: 422, column: 21, scope: !359)
!490 = !DILocation(line: 424, column: 21, scope: !359)
!491 = !DILocation(line: 425, column: 21, scope: !359)
!492 = !DILocation(line: 429, column: 25, scope: !359)
!493 = !DILocation(line: 430, column: 29, scope: !359)
!494 = !DILocation(line: 431, column: 29, scope: !359)
!495 = !DILocation(line: 432, column: 33, scope: !359)
!496 = !DILocation(line: 434, column: 29, scope: !359)
!497 = !DILocation(line: 435, column: 29, scope: !359)
!498 = !DILocation(line: 437, column: 29, scope: !359)
!499 = !DILocation(line: 438, column: 29, scope: !359)
!500 = !DILocation(line: 439, column: 29, scope: !359)
!501 = !DILocation(line: 441, column: 25, scope: !359)
!502 = !DILocation(line: 443, column: 25, scope: !359)
!503 = !DILocation(line: 444, column: 25, scope: !359)
!504 = !DILocation(line: 445, column: 29, scope: !359)
!505 = !DILocation(line: 450, column: 25, scope: !359)
!506 = !DILocation(line: 451, column: 25, scope: !359)
!507 = !DILocation(line: 453, column: 21, scope: !359)
!508 = !DILocation(line: 454, column: 21, scope: !359)
!509 = !DILocation(line: 459, column: 9, scope: !359)
!510 = !DILocation(line: 462, column: 5, scope: !359)
!511 = !DILocation(line: 465, column: 9, scope: !359)
!512 = !DILocation(line: 468, column: 5, scope: !359)
!513 = !DILocation(line: 469, column: 5, scope: !359)
!514 = !DILocation(line: 470, column: 9, scope: !359)
!515 = !DILocation(line: 472, column: 5, scope: !359)
!516 = !DILocation(line: 495, column: 5, scope: !359)
!517 = !DILocation(line: 496, column: 5, scope: !359)
!518 = !DILocation(line: 497, column: 5, scope: !359)
!519 = !DILocation(line: 498, column: 5, scope: !359)
!520 = !DILocation(line: 499, column: 5, scope: !359)
!521 = !DILocation(line: 505, column: 5, scope: !359)
!522 = !DILocation(line: 506, column: 5, scope: !359)
!523 = !DILocation(line: 507, column: 9, scope: !359)
!524 = !DILocation(line: 508, column: 9, scope: !359)
!525 = !DILocation(line: 509, column: 9, scope: !359)
!526 = !DILocation(line: 510, column: 13, scope: !359)
!527 = !DILocation(line: 511, column: 13, scope: !359)
!528 = !DILocation(line: 512, column: 17, scope: !359)
!529 = !DILocation(line: 514, column: 17, scope: !359)
!530 = !DILocation(line: 518, column: 9, scope: !359)
!531 = !DILocation(line: 519, column: 13, scope: !359)
!532 = !DILocation(line: 520, column: 17, scope: !359)
!533 = !DILocation(line: 523, column: 13, scope: !359)
!534 = !DILocation(line: 524, column: 13, scope: !359)
!535 = !DILocation(line: 525, column: 13, scope: !359)
!536 = !DILocation(line: 526, column: 13, scope: !359)
!537 = !DILocation(line: 527, column: 13, scope: !359)
!538 = !DILocation(line: 528, column: 13, scope: !359)
!539 = !DILocation(line: 530, column: 13, scope: !359)
!540 = !DILocation(line: 531, column: 17, scope: !359)
!541 = !DILocation(line: 532, column: 17, scope: !359)
!542 = !DILocation(line: 533, column: 21, scope: !359)
!543 = !DILocation(line: 534, column: 21, scope: !359)
!544 = !DILocation(line: 535, column: 25, scope: !359)
!545 = !DILocation(line: 537, column: 21, scope: !359)
!546 = !DILocation(line: 539, column: 21, scope: !359)
!547 = !DILocation(line: 541, column: 17, scope: !359)
!548 = !DILocation(line: 542, column: 21, scope: !359)
!549 = !DILocation(line: 543, column: 21, scope: !359)
!550 = !DILocation(line: 544, column: 21, scope: !359)
!551 = !DILocation(line: 545, column: 25, scope: !359)
!552 = !DILocation(line: 547, column: 21, scope: !359)
!553 = !DILocation(line: 548, column: 21, scope: !359)
!554 = !DILocation(line: 552, column: 21, scope: !359)
!555 = !DILocation(line: 553, column: 21, scope: !359)
!556 = !DILocation(line: 555, column: 21, scope: !359)
!557 = !DILocation(line: 558, column: 17, scope: !359)
!558 = !DILocation(line: 559, column: 21, scope: !359)
!559 = !DILocation(line: 561, column: 17, scope: !359)
!560 = !DILocation(line: 562, column: 21, scope: !359)
!561 = !DILocation(line: 564, column: 21, scope: !359)
!562 = !DILocation(line: 566, column: 17, scope: !359)
!563 = !DILocation(line: 567, column: 17, scope: !359)
!564 = !DILocation(line: 568, column: 21, scope: !359)
!565 = !DILocation(line: 571, column: 25, scope: !359)
!566 = !DILocation(line: 577, column: 25, scope: !359)
!567 = !DILocation(line: 578, column: 25, scope: !359)
!568 = !DILocation(line: 579, column: 29, scope: !359)
!569 = !DILocation(line: 582, column: 25, scope: !359)
!570 = !DILocation(line: 584, column: 21, scope: !359)
!571 = !DILocation(line: 586, column: 21, scope: !359)
!572 = !DILocation(line: 589, column: 17, scope: !359)
!573 = !DILocation(line: 590, column: 17, scope: !359)
!574 = !DILocation(line: 591, column: 17, scope: !359)
!575 = !DILocation(line: 592, column: 21, scope: !359)
!576 = !DILocation(line: 593, column: 21, scope: !359)
!577 = !DILocation(line: 594, column: 25, scope: !359)
!578 = !DILocation(line: 595, column: 57, scope: !359)
!579 = !DILocation(line: 595, column: 25, scope: !359)
!580 = !DILocation(line: 595, column: 50, scope: !359)
!581 = !DILocation(line: 596, column: 29, scope: !359)
!582 = !DILocation(line: 597, column: 29, scope: !359)
!583 = !DILocation(line: 598, column: 29, scope: !359)
!584 = !DILocation(line: 599, column: 29, scope: !359)
!585 = !DILocation(line: 601, column: 25, scope: !359)
!586 = !DILocation(line: 602, column: 29, scope: !359)
!587 = !DILocation(line: 605, column: 25, scope: !359)
!588 = !DILocation(line: 607, column: 21, scope: !359)
!589 = !DILocation(line: 609, column: 17, scope: !359)
!590 = !DILocation(line: 610, column: 17, scope: !359)
!591 = !DILocation(line: 612, column: 17, scope: !359)
!592 = !DILocation(line: 613, column: 17, scope: !359)
!593 = !DILocation(line: 614, column: 17, scope: !359)
!594 = !DILocation(line: 615, column: 21, scope: !359)
!595 = !DILocation(line: 616, column: 21, scope: !359)
!596 = !DILocation(line: 617, column: 25, scope: !359)
!597 = !DILocation(line: 618, column: 57, scope: !359)
!598 = !DILocation(line: 618, column: 25, scope: !359)
!599 = !DILocation(line: 618, column: 50, scope: !359)
!600 = !DILocation(line: 619, column: 29, scope: !359)
!601 = !DILocation(line: 620, column: 29, scope: !359)
!602 = !DILocation(line: 621, column: 29, scope: !359)
!603 = !DILocation(line: 622, column: 29, scope: !359)
!604 = !DILocation(line: 623, column: 29, scope: !359)
!605 = !DILocation(line: 625, column: 25, scope: !359)
!606 = !DILocation(line: 626, column: 29, scope: !359)
!607 = !DILocation(line: 629, column: 25, scope: !359)
!608 = !DILocation(line: 631, column: 21, scope: !359)
!609 = !DILocation(line: 633, column: 17, scope: !359)
!610 = !DILocation(line: 634, column: 17, scope: !359)
!611 = !DILocation(line: 636, column: 17, scope: !359)
!612 = !DILocation(line: 637, column: 17, scope: !359)
!613 = !DILocation(line: 638, column: 17, scope: !359)
!614 = !DILocation(line: 639, column: 21, scope: !359)
!615 = !DILocation(line: 640, column: 21, scope: !359)
!616 = !DILocation(line: 641, column: 25, scope: !359)
!617 = !DILocation(line: 642, column: 57, scope: !359)
!618 = !DILocation(line: 642, column: 25, scope: !359)
!619 = !DILocation(line: 642, column: 50, scope: !359)
!620 = !DILocation(line: 643, column: 29, scope: !359)
!621 = !DILocation(line: 644, column: 29, scope: !359)
!622 = !DILocation(line: 645, column: 29, scope: !359)
!623 = !DILocation(line: 647, column: 25, scope: !359)
!624 = !DILocation(line: 648, column: 29, scope: !359)
!625 = !DILocation(line: 651, column: 25, scope: !359)
!626 = !DILocation(line: 653, column: 21, scope: !359)
!627 = !DILocation(line: 655, column: 17, scope: !359)
!628 = !DILocation(line: 656, column: 17, scope: !359)
!629 = !DILocation(line: 658, column: 17, scope: !359)
!630 = !DILocation(line: 659, column: 17, scope: !359)
!631 = !DILocation(line: 660, column: 17, scope: !359)
!632 = !DILocation(line: 661, column: 21, scope: !359)
!633 = !DILocation(line: 663, column: 17, scope: !359)
!634 = !DILocation(line: 664, column: 17, scope: !359)
!635 = !DILocation(line: 666, column: 17, scope: !359)
!636 = !DILocation(line: 669, column: 13, scope: !359)
!637 = !DILocation(line: 670, column: 17, scope: !359)
!638 = !DILocation(line: 672, column: 17, scope: !359)
!639 = !DILocation(line: 674, column: 17, scope: !359)
!640 = !DILocation(line: 676, column: 17, scope: !359)
!641 = !DILocation(line: 678, column: 17, scope: !359)
!642 = !DILocation(line: 680, column: 17, scope: !359)
!643 = !DILocation(line: 682, column: 13, scope: !359)
!644 = !DILocation(line: 684, column: 13, scope: !359)
!645 = !DILocation(line: 685, column: 17, scope: !359)
!646 = !DILocation(line: 687, column: 13, scope: !359)
!647 = !DILocation(line: 689, column: 13, scope: !359)
!648 = !DILocation(line: 690, column: 17, scope: !359)
!649 = !DILocation(line: 692, column: 13, scope: !359)
!650 = !DILocation(line: 693, column: 13, scope: !359)
!651 = !DILocation(line: 694, column: 13, scope: !359)
!652 = !DILocation(line: 695, column: 13, scope: !359)
!653 = !DILocation(line: 696, column: 13, scope: !359)
!654 = !DILocation(line: 697, column: 13, scope: !359)
!655 = !DILocation(line: 698, column: 17, scope: !359)
!656 = !DILocation(line: 699, column: 21, scope: !359)
!657 = !DILocation(line: 701, column: 17, scope: !359)
!658 = !DILocation(line: 702, column: 17, scope: !359)
!659 = !DILocation(line: 703, column: 17, scope: !359)
!660 = !DILocation(line: 705, column: 17, scope: !359)
!661 = !DILocation(line: 706, column: 21, scope: !359)
!662 = !DILocation(line: 708, column: 21, scope: !359)
!663 = !DILocation(line: 709, column: 21, scope: !359)
!664 = !DILocation(line: 710, column: 25, scope: !359)
!665 = !DILocation(line: 712, column: 21, scope: !359)
!666 = !DILocation(line: 713, column: 21, scope: !359)
!667 = !DILocation(line: 715, column: 21, scope: !359)
!668 = !DILocation(line: 718, column: 17, scope: !359)
!669 = !DILocation(line: 719, column: 21, scope: !359)
!670 = !DILocation(line: 720, column: 25, scope: !359)
!671 = !DILocation(line: 722, column: 21, scope: !359)
!672 = !DILocation(line: 723, column: 21, scope: !359)
!673 = !DILocation(line: 724, column: 25, scope: !359)
!674 = !DILocation(line: 726, column: 21, scope: !359)
!675 = !DILocation(line: 727, column: 21, scope: !359)
!676 = !DILocation(line: 728, column: 21, scope: !359)
!677 = !DILocation(line: 729, column: 25, scope: !359)
!678 = !DILocation(line: 730, column: 25, scope: !359)
!679 = !DILocation(line: 731, column: 29, scope: !359)
!680 = !DILocation(line: 733, column: 29, scope: !359)
!681 = !DILocation(line: 737, column: 17, scope: !359)
!682 = !DILocation(line: 738, column: 21, scope: !359)
!683 = !DILocation(line: 740, column: 17, scope: !359)
!684 = !DILocation(line: 741, column: 17, scope: !359)
!685 = !DILocation(line: 742, column: 21, scope: !359)
!686 = !DILocation(line: 744, column: 17, scope: !359)
!687 = !DILocation(line: 745, column: 17, scope: !359)
!688 = !DILocation(line: 746, column: 21, scope: !359)
!689 = !DILocation(line: 748, column: 17, scope: !359)
!690 = !DILocation(line: 749, column: 17, scope: !359)
!691 = !DILocation(line: 750, column: 17, scope: !359)
!692 = !DILocation(line: 751, column: 17, scope: !359)
!693 = !DILocation(line: 752, column: 17, scope: !359)
!694 = !DILocation(line: 753, column: 17, scope: !359)
!695 = !DILocation(line: 754, column: 17, scope: !359)
!696 = !DILocation(line: 755, column: 17, scope: !359)
!697 = !DILocation(line: 756, column: 17, scope: !359)
!698 = !DILocation(line: 757, column: 17, scope: !359)
!699 = !DILocation(line: 758, column: 21, scope: !359)
!700 = !DILocation(line: 759, column: 21, scope: !359)
!701 = !DILocation(line: 760, column: 25, scope: !359)
!702 = !DILocation(line: 762, column: 25, scope: !359)
!703 = !DILocation(line: 765, column: 17, scope: !359)
!704 = !DILocation(line: 766, column: 21, scope: !359)
!705 = !DILocation(line: 768, column: 17, scope: !359)
!706 = !DILocation(line: 769, column: 21, scope: !359)
!707 = !DILocation(line: 771, column: 17, scope: !359)
!708 = !DILocation(line: 772, column: 17, scope: !359)
!709 = !DILocation(line: 773, column: 17, scope: !359)
!710 = !DILocation(line: 778, column: 5, scope: !359)
!711 = distinct !DISubprogram(name: "__nuppConst_decodeFused_f007fffb3d50ef9f", scope: !0, file: !0, line: 138, type: !4, scopeLine: 138, spFlags: DISPFlagDefinition | DISPFlagOptimized, unit: !1)
!712 = !DILocation(line: 138, column: 1, scope: !711)
!713 = !DILocation(line: 138, column: 5, scope: !711)
!714 = !DILocation(line: 139, column: 5, scope: !711)
!715 = !DILocation(line: 140, column: 9, scope: !711)
!716 = !DILocation(line: 143, column: 5, scope: !711)
!717 = !DILocation(line: 144, column: 5, scope: !711)
!718 = !DILocation(line: 145, column: 5, scope: !711)
!719 = !DILocation(line: 146, column: 5, scope: !711)
!720 = !DILocation(line: 147, column: 5, scope: !711)
!721 = !DILocation(line: 152, column: 5, scope: !711)
!722 = !DILocation(line: 153, column: 5, scope: !711)
!723 = !DILocation(line: 154, column: 5, scope: !711)
!724 = !DILocation(line: 159, column: 5, scope: !711)
!725 = !DILocation(line: 160, column: 5, scope: !711)
!726 = !DILocation(line: 161, column: 5, scope: !711)
!727 = !DILocation(line: 162, column: 5, scope: !711)
!728 = !DILocation(line: 163, column: 5, scope: !711)
!729 = !DILocation(line: 166, column: 5, scope: !711)
!730 = !DILocation(line: 167, column: 5, scope: !711)
!731 = !DILocation(line: 171, column: 5, scope: !711)
!732 = !DILocation(line: 178, column: 5, scope: !711)
!733 = !DILocation(line: 179, column: 9, scope: !711)
!734 = !DILocation(line: 180, column: 9, scope: !711)
!735 = !DILocation(line: 181, column: 9, scope: !711)
!736 = !DILocation(line: 182, column: 13, scope: !711)
!737 = !DILocation(line: 184, column: 17, scope: !711)
!738 = !DILocation(line: 185, column: 17, scope: !711)
!739 = !DILocation(line: 186, column: 17, scope: !711)
!740 = !DILocation(line: 187, column: 17, scope: !711)
!741 = !DILocation(line: 188, column: 17, scope: !711)
!742 = !DILocation(line: 189, column: 17, scope: !711)
!743 = !DILocation(line: 190, column: 17, scope: !711)
!744 = !DILocation(line: 191, column: 21, scope: !711)
!745 = !DILocation(line: 192, column: 21, scope: !711)
!746 = !DILocation(line: 194, column: 21, scope: !711)
!747 = !DILocation(line: 198, column: 21, scope: !711)
!748 = !DILocation(line: 199, column: 21, scope: !711)
!749 = !DILocation(line: 200, column: 25, scope: !711)
!750 = !DILocation(line: 201, column: 25, scope: !711)
!751 = !DILocation(line: 204, column: 29, scope: !711)
!752 = !DILocation(line: 211, column: 17, scope: !711)
!753 = !DILocation(line: 218, column: 21, scope: !711)
!754 = !DILocation(line: 219, column: 21, scope: !711)
!755 = !DILocation(line: 220, column: 21, scope: !711)
!756 = !DILocation(line: 221, column: 21, scope: !711)
!757 = !DILocation(line: 230, column: 21, scope: !711)
!758 = !DILocation(line: 231, column: 21, scope: !711)
!759 = !DILocation(line: 232, column: 21, scope: !711)
!760 = !DILocation(line: 251, column: 21, scope: !711)
!761 = !DILocation(line: 252, column: 21, scope: !711)
!762 = !DILocation(line: 260, column: 21, scope: !711)
!763 = !DILocation(line: 261, column: 21, scope: !711)
!764 = !DILocation(line: 269, column: 25, scope: !711)
!765 = !DILocation(line: 274, column: 25, scope: !711)
!766 = !DILocation(line: 277, column: 21, scope: !711)
!767 = !DILocation(line: 279, column: 17, scope: !711)
!768 = !DILocation(line: 280, column: 21, scope: !711)
!769 = !DILocation(line: 282, column: 21, scope: !711)
!770 = !DILocation(line: 286, column: 9, scope: !711)
!771 = !DILocation(line: 292, column: 13, scope: !711)
!772 = !DILocation(line: 293, column: 13, scope: !711)
!773 = !DILocation(line: 294, column: 13, scope: !711)
!774 = !DILocation(line: 295, column: 13, scope: !711)
!775 = !DILocation(line: 296, column: 17, scope: !711)
!776 = !DILocation(line: 297, column: 17, scope: !711)
!777 = !DILocation(line: 298, column: 21, scope: !711)
!778 = !DILocation(line: 303, column: 21, scope: !711)
!779 = !DILocation(line: 304, column: 25, scope: !711)
!780 = !DILocation(line: 306, column: 21, scope: !711)
!781 = !DILocation(line: 307, column: 21, scope: !711)
!782 = !DILocation(line: 308, column: 25, scope: !711)
!783 = !DILocation(line: 310, column: 25, scope: !711)
!784 = !DILocation(line: 312, column: 21, scope: !711)
!785 = !DILocation(line: 313, column: 25, scope: !711)
!786 = !DILocation(line: 314, column: 25, scope: !711)
!787 = !DILocation(line: 315, column: 25, scope: !711)
!788 = !DILocation(line: 318, column: 25, scope: !711)
!789 = !DILocation(line: 319, column: 29, scope: !711)
!790 = !DILocation(line: 320, column: 33, scope: !711)
!791 = !DILocation(line: 322, column: 33, scope: !711)
!792 = !DILocation(line: 324, column: 33, scope: !711)
!793 = !DILocation(line: 326, column: 33, scope: !711)
!794 = !DILocation(line: 330, column: 21, scope: !711)
!795 = !DILocation(line: 332, column: 21, scope: !711)
!796 = !DILocation(line: 339, column: 13, scope: !711)
!797 = !DILocation(line: 340, column: 17, scope: !711)
!798 = !DILocation(line: 341, column: 17, scope: !711)
!799 = !DILocation(line: 352, column: 21, scope: !711)
!800 = !DILocation(line: 355, column: 13, scope: !711)
!801 = !DILocation(line: 358, column: 9, scope: !711)
!802 = !DILocation(line: 359, column: 13, scope: !711)
!803 = !DILocation(line: 360, column: 13, scope: !711)
!804 = !DILocation(line: 361, column: 13, scope: !711)
!805 = !DILocation(line: 362, column: 13, scope: !711)
!806 = !DILocation(line: 363, column: 17, scope: !711)
!807 = !DILocation(line: 367, column: 17, scope: !711)
!808 = !DILocation(line: 368, column: 21, scope: !711)
!809 = !DILocation(line: 370, column: 17, scope: !711)
!810 = !DILocation(line: 371, column: 21, scope: !711)
!811 = !DILocation(line: 372, column: 21, scope: !711)
!812 = !DILocation(line: 373, column: 25, scope: !711)
!813 = !DILocation(line: 374, column: 29, scope: !711)
!814 = !DILocation(line: 376, column: 25, scope: !711)
!815 = !DILocation(line: 380, column: 25, scope: !711)
!816 = !DILocation(line: 381, column: 29, scope: !711)
!817 = !DILocation(line: 383, column: 25, scope: !711)
!818 = !DILocation(line: 384, column: 25, scope: !711)
!819 = !DILocation(line: 386, column: 25, scope: !711)
!820 = !DILocation(line: 388, column: 25, scope: !711)
!821 = !DILocation(line: 390, column: 25, scope: !711)
!822 = !DILocation(line: 391, column: 25, scope: !711)
!823 = !DILocation(line: 392, column: 29, scope: !711)
!824 = !DILocation(line: 394, column: 29, scope: !711)
!825 = !DILocation(line: 397, column: 25, scope: !711)
!826 = !DILocation(line: 398, column: 25, scope: !711)
!827 = !DILocation(line: 399, column: 29, scope: !711)
!828 = !DILocation(line: 401, column: 29, scope: !711)
!829 = !DILocation(line: 404, column: 21, scope: !711)
!830 = !DILocation(line: 405, column: 21, scope: !711)
!831 = !DILocation(line: 406, column: 21, scope: !711)
!832 = !DILocation(line: 407, column: 21, scope: !711)
!833 = !DILocation(line: 410, column: 21, scope: !711)
!834 = !DILocation(line: 412, column: 21, scope: !711)
!835 = !DILocation(line: 413, column: 25, scope: !711)
!836 = !DILocation(line: 415, column: 21, scope: !711)
!837 = !DILocation(line: 416, column: 25, scope: !711)
!838 = !DILocation(line: 418, column: 25, scope: !711)
!839 = !DILocation(line: 420, column: 21, scope: !711)
!840 = !DILocation(line: 421, column: 21, scope: !711)
!841 = !DILocation(line: 422, column: 21, scope: !711)
!842 = !DILocation(line: 424, column: 21, scope: !711)
!843 = !DILocation(line: 425, column: 21, scope: !711)
!844 = !DILocation(line: 429, column: 25, scope: !711)
!845 = !DILocation(line: 430, column: 29, scope: !711)
!846 = !DILocation(line: 431, column: 29, scope: !711)
!847 = !DILocation(line: 432, column: 33, scope: !711)
!848 = !DILocation(line: 434, column: 29, scope: !711)
!849 = !DILocation(line: 435, column: 29, scope: !711)
!850 = !DILocation(line: 437, column: 29, scope: !711)
!851 = !DILocation(line: 438, column: 29, scope: !711)
!852 = !DILocation(line: 439, column: 29, scope: !711)
!853 = !DILocation(line: 441, column: 25, scope: !711)
!854 = !DILocation(line: 443, column: 25, scope: !711)
!855 = !DILocation(line: 444, column: 25, scope: !711)
!856 = !DILocation(line: 445, column: 29, scope: !711)
!857 = !DILocation(line: 450, column: 25, scope: !711)
!858 = !DILocation(line: 451, column: 25, scope: !711)
!859 = !DILocation(line: 453, column: 21, scope: !711)
!860 = !DILocation(line: 454, column: 21, scope: !711)
!861 = !DILocation(line: 459, column: 9, scope: !711)
!862 = !DILocation(line: 462, column: 5, scope: !711)
!863 = !DILocation(line: 465, column: 9, scope: !711)
!864 = !DILocation(line: 468, column: 5, scope: !711)
!865 = !DILocation(line: 469, column: 5, scope: !711)
!866 = !DILocation(line: 470, column: 9, scope: !711)
!867 = !DILocation(line: 472, column: 5, scope: !711)
!868 = !DILocation(line: 495, column: 5, scope: !711)
!869 = !DILocation(line: 496, column: 5, scope: !711)
!870 = !DILocation(line: 497, column: 5, scope: !711)
!871 = !DILocation(line: 498, column: 5, scope: !711)
!872 = !DILocation(line: 499, column: 5, scope: !711)
!873 = !DILocation(line: 505, column: 5, scope: !711)
!874 = !DILocation(line: 506, column: 5, scope: !711)
!875 = !DILocation(line: 507, column: 9, scope: !711)
!876 = !DILocation(line: 508, column: 9, scope: !711)
!877 = !DILocation(line: 509, column: 9, scope: !711)
!878 = !DILocation(line: 510, column: 13, scope: !711)
!879 = !DILocation(line: 511, column: 13, scope: !711)
!880 = !DILocation(line: 512, column: 17, scope: !711)
!881 = !DILocation(line: 514, column: 17, scope: !711)
!882 = !DILocation(line: 518, column: 9, scope: !711)
!883 = !DILocation(line: 519, column: 13, scope: !711)
!884 = !DILocation(line: 520, column: 17, scope: !711)
!885 = !DILocation(line: 523, column: 13, scope: !711)
!886 = !DILocation(line: 524, column: 13, scope: !711)
!887 = !DILocation(line: 525, column: 13, scope: !711)
!888 = !DILocation(line: 526, column: 13, scope: !711)
!889 = !DILocation(line: 527, column: 13, scope: !711)
!890 = !DILocation(line: 528, column: 13, scope: !711)
!891 = !DILocation(line: 530, column: 13, scope: !711)
!892 = !DILocation(line: 531, column: 17, scope: !711)
!893 = !DILocation(line: 532, column: 17, scope: !711)
!894 = !DILocation(line: 533, column: 21, scope: !711)
!895 = !DILocation(line: 534, column: 21, scope: !711)
!896 = !DILocation(line: 535, column: 25, scope: !711)
!897 = !DILocation(line: 537, column: 21, scope: !711)
!898 = !DILocation(line: 539, column: 21, scope: !711)
!899 = !DILocation(line: 541, column: 17, scope: !711)
!900 = !DILocation(line: 542, column: 21, scope: !711)
!901 = !DILocation(line: 543, column: 21, scope: !711)
!902 = !DILocation(line: 544, column: 21, scope: !711)
!903 = !DILocation(line: 545, column: 25, scope: !711)
!904 = !DILocation(line: 547, column: 21, scope: !711)
!905 = !DILocation(line: 548, column: 21, scope: !711)
!906 = !DILocation(line: 552, column: 21, scope: !711)
!907 = !DILocation(line: 553, column: 21, scope: !711)
!908 = !DILocation(line: 555, column: 21, scope: !711)
!909 = !DILocation(line: 558, column: 17, scope: !711)
!910 = !DILocation(line: 559, column: 21, scope: !711)
!911 = !DILocation(line: 561, column: 17, scope: !711)
!912 = !DILocation(line: 562, column: 21, scope: !711)
!913 = !DILocation(line: 564, column: 21, scope: !711)
!914 = !DILocation(line: 566, column: 17, scope: !711)
!915 = !DILocation(line: 567, column: 17, scope: !711)
!916 = !DILocation(line: 568, column: 21, scope: !711)
!917 = !DILocation(line: 571, column: 25, scope: !711)
!918 = !DILocation(line: 577, column: 25, scope: !711)
!919 = !DILocation(line: 578, column: 25, scope: !711)
!920 = !DILocation(line: 579, column: 29, scope: !711)
!921 = !DILocation(line: 582, column: 25, scope: !711)
!922 = !DILocation(line: 584, column: 21, scope: !711)
!923 = !DILocation(line: 586, column: 21, scope: !711)
!924 = !DILocation(line: 589, column: 17, scope: !711)
!925 = !DILocation(line: 590, column: 17, scope: !711)
!926 = !DILocation(line: 591, column: 17, scope: !711)
!927 = !DILocation(line: 592, column: 21, scope: !711)
!928 = !DILocation(line: 593, column: 21, scope: !711)
!929 = !DILocation(line: 594, column: 25, scope: !711)
!930 = !DILocation(line: 595, column: 57, scope: !711)
!931 = !DILocation(line: 595, column: 25, scope: !711)
!932 = !DILocation(line: 595, column: 50, scope: !711)
!933 = !DILocation(line: 596, column: 29, scope: !711)
!934 = !DILocation(line: 597, column: 29, scope: !711)
!935 = !DILocation(line: 598, column: 29, scope: !711)
!936 = !DILocation(line: 599, column: 29, scope: !711)
!937 = !DILocation(line: 601, column: 25, scope: !711)
!938 = !DILocation(line: 602, column: 29, scope: !711)
!939 = !DILocation(line: 605, column: 25, scope: !711)
!940 = !DILocation(line: 607, column: 21, scope: !711)
!941 = !DILocation(line: 609, column: 17, scope: !711)
!942 = !DILocation(line: 610, column: 17, scope: !711)
!943 = !DILocation(line: 612, column: 17, scope: !711)
!944 = !DILocation(line: 613, column: 17, scope: !711)
!945 = !DILocation(line: 614, column: 17, scope: !711)
!946 = !DILocation(line: 615, column: 21, scope: !711)
!947 = !DILocation(line: 616, column: 21, scope: !711)
!948 = !DILocation(line: 617, column: 25, scope: !711)
!949 = !DILocation(line: 618, column: 57, scope: !711)
!950 = !DILocation(line: 618, column: 25, scope: !711)
!951 = !DILocation(line: 618, column: 50, scope: !711)
!952 = !DILocation(line: 619, column: 29, scope: !711)
!953 = !DILocation(line: 620, column: 29, scope: !711)
!954 = !DILocation(line: 621, column: 29, scope: !711)
!955 = !DILocation(line: 622, column: 29, scope: !711)
!956 = !DILocation(line: 623, column: 29, scope: !711)
!957 = !DILocation(line: 625, column: 25, scope: !711)
!958 = !DILocation(line: 626, column: 29, scope: !711)
!959 = !DILocation(line: 629, column: 25, scope: !711)
!960 = !DILocation(line: 631, column: 21, scope: !711)
!961 = !DILocation(line: 633, column: 17, scope: !711)
!962 = !DILocation(line: 634, column: 17, scope: !711)
!963 = !DILocation(line: 636, column: 17, scope: !711)
!964 = !DILocation(line: 637, column: 17, scope: !711)
!965 = !DILocation(line: 638, column: 17, scope: !711)
!966 = !DILocation(line: 639, column: 21, scope: !711)
!967 = !DILocation(line: 640, column: 21, scope: !711)
!968 = !DILocation(line: 641, column: 25, scope: !711)
!969 = !DILocation(line: 642, column: 57, scope: !711)
!970 = !DILocation(line: 642, column: 25, scope: !711)
!971 = !DILocation(line: 642, column: 50, scope: !711)
!972 = !DILocation(line: 643, column: 29, scope: !711)
!973 = !DILocation(line: 644, column: 29, scope: !711)
!974 = !DILocation(line: 645, column: 29, scope: !711)
!975 = !DILocation(line: 647, column: 25, scope: !711)
!976 = !DILocation(line: 648, column: 29, scope: !711)
!977 = !DILocation(line: 651, column: 25, scope: !711)
!978 = !DILocation(line: 653, column: 21, scope: !711)
!979 = !DILocation(line: 655, column: 17, scope: !711)
!980 = !DILocation(line: 656, column: 17, scope: !711)
!981 = !DILocation(line: 658, column: 17, scope: !711)
!982 = !DILocation(line: 659, column: 17, scope: !711)
!983 = !DILocation(line: 660, column: 17, scope: !711)
!984 = !DILocation(line: 661, column: 21, scope: !711)
!985 = !DILocation(line: 663, column: 17, scope: !711)
!986 = !DILocation(line: 664, column: 17, scope: !711)
!987 = !DILocation(line: 666, column: 17, scope: !711)
!988 = !DILocation(line: 669, column: 13, scope: !711)
!989 = !DILocation(line: 670, column: 17, scope: !711)
!990 = !DILocation(line: 672, column: 17, scope: !711)
!991 = !DILocation(line: 674, column: 17, scope: !711)
!992 = !DILocation(line: 676, column: 17, scope: !711)
!993 = !DILocation(line: 678, column: 17, scope: !711)
!994 = !DILocation(line: 680, column: 17, scope: !711)
!995 = !DILocation(line: 682, column: 13, scope: !711)
!996 = !DILocation(line: 684, column: 13, scope: !711)
!997 = !DILocation(line: 685, column: 17, scope: !711)
!998 = !DILocation(line: 687, column: 13, scope: !711)
!999 = !DILocation(line: 689, column: 13, scope: !711)
!1000 = !DILocation(line: 690, column: 17, scope: !711)
!1001 = !DILocation(line: 692, column: 13, scope: !711)
!1002 = !DILocation(line: 693, column: 13, scope: !711)
!1003 = !DILocation(line: 694, column: 13, scope: !711)
!1004 = !DILocation(line: 695, column: 13, scope: !711)
!1005 = !DILocation(line: 696, column: 13, scope: !711)
!1006 = !DILocation(line: 697, column: 13, scope: !711)
!1007 = !DILocation(line: 698, column: 17, scope: !711)
!1008 = !DILocation(line: 699, column: 21, scope: !711)
!1009 = !DILocation(line: 701, column: 17, scope: !711)
!1010 = !DILocation(line: 702, column: 17, scope: !711)
!1011 = !DILocation(line: 703, column: 17, scope: !711)
!1012 = !DILocation(line: 705, column: 17, scope: !711)
!1013 = !DILocation(line: 706, column: 21, scope: !711)
!1014 = !DILocation(line: 708, column: 21, scope: !711)
!1015 = !DILocation(line: 709, column: 21, scope: !711)
!1016 = !DILocation(line: 710, column: 25, scope: !711)
!1017 = !DILocation(line: 712, column: 21, scope: !711)
!1018 = !DILocation(line: 713, column: 21, scope: !711)
!1019 = !DILocation(line: 715, column: 21, scope: !711)
!1020 = !DILocation(line: 718, column: 17, scope: !711)
!1021 = !DILocation(line: 719, column: 21, scope: !711)
!1022 = !DILocation(line: 720, column: 25, scope: !711)
!1023 = !DILocation(line: 722, column: 21, scope: !711)
!1024 = !DILocation(line: 723, column: 21, scope: !711)
!1025 = !DILocation(line: 724, column: 25, scope: !711)
!1026 = !DILocation(line: 726, column: 21, scope: !711)
!1027 = !DILocation(line: 727, column: 21, scope: !711)
!1028 = !DILocation(line: 728, column: 21, scope: !711)
!1029 = !DILocation(line: 729, column: 25, scope: !711)
!1030 = !DILocation(line: 730, column: 25, scope: !711)
!1031 = !DILocation(line: 731, column: 29, scope: !711)
!1032 = !DILocation(line: 733, column: 29, scope: !711)
!1033 = !DILocation(line: 737, column: 17, scope: !711)
!1034 = !DILocation(line: 738, column: 21, scope: !711)
!1035 = !DILocation(line: 740, column: 17, scope: !711)
!1036 = !DILocation(line: 741, column: 17, scope: !711)
!1037 = !DILocation(line: 742, column: 21, scope: !711)
!1038 = !DILocation(line: 744, column: 17, scope: !711)
!1039 = !DILocation(line: 745, column: 17, scope: !711)
!1040 = !DILocation(line: 746, column: 21, scope: !711)
!1041 = !DILocation(line: 748, column: 17, scope: !711)
!1042 = !DILocation(line: 749, column: 17, scope: !711)
!1043 = !DILocation(line: 750, column: 17, scope: !711)
!1044 = !DILocation(line: 751, column: 17, scope: !711)
!1045 = !DILocation(line: 752, column: 17, scope: !711)
!1046 = !DILocation(line: 753, column: 17, scope: !711)
!1047 = !DILocation(line: 754, column: 17, scope: !711)
!1048 = !DILocation(line: 755, column: 17, scope: !711)
!1049 = !DILocation(line: 756, column: 17, scope: !711)
!1050 = !DILocation(line: 757, column: 17, scope: !711)
!1051 = !DILocation(line: 758, column: 21, scope: !711)
!1052 = !DILocation(line: 759, column: 21, scope: !711)
!1053 = !DILocation(line: 760, column: 25, scope: !711)
!1054 = !DILocation(line: 762, column: 25, scope: !711)
!1055 = !DILocation(line: 765, column: 17, scope: !711)
!1056 = !DILocation(line: 766, column: 21, scope: !711)
!1057 = !DILocation(line: 768, column: 17, scope: !711)
!1058 = !DILocation(line: 769, column: 21, scope: !711)
!1059 = !DILocation(line: 771, column: 17, scope: !711)
!1060 = !DILocation(line: 772, column: 17, scope: !711)
!1061 = !DILocation(line: 773, column: 17, scope: !711)
!1062 = !DILocation(line: 778, column: 5, scope: !711)
