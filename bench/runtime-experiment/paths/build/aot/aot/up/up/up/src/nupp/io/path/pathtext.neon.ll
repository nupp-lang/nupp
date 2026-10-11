@ks.rt = internal global ptr null
declare i32 @lua_checkstack(ptr, i32)
declare ptr @luaL_checklstring(ptr, i32, ptr)
declare i32 @lua_toboolean(ptr, i32)
declare i32 @lua_gettop(ptr)
declare void @lua_settop(ptr, i32)
@nupp.bytes.1 = private unnamed_addr constant [25 x i8] c"array capacity at 209:30\00", align 1
@nupp.bytes.2 = private unnamed_addr constant [24 x i8] c"hash capacity at 209:30\00", align 1
declare void @lua_createtable(ptr, i32, i32)
declare void @lua_replace(ptr, i32)
@nupp.bytes.3 = private unnamed_addr constant [7 x i8] c"284:20\00", align 1
declare void @lua_pushnumber(ptr, double)
@nupp.bytes.4 = private unnamed_addr constant [7 x i8] c"295:17\00", align 1
declare void @lua_rawseti(ptr, i32, i32)
@nupp.bytes.5 = private unnamed_addr constant [1 x i8] c".", align 1
declare void @lua_pushlstring(ptr, ptr, i64)
@nupp.bytes.6 = private unnamed_addr constant [0 x i8] c"", align 1
@nupp.bytes.7 = private unnamed_addr constant [1 x i8] c"/", align 1
@nupp.bytes.8 = private unnamed_addr constant [7 x i8] c"326:23\00", align 1
@nupp.bytes.9 = private unnamed_addr constant [2 x i8] c"..", align 1
@nupp.bytes.10 = private unnamed_addr constant [3 x i8] c"%s\00", align 1
@nupp.bytes.11 = private unnamed_addr constant [32 x i8] c"AOT builder Lua stack exhausted\00", align 1
declare i32 @luaL_error(ptr, ptr, ...)
declare i32 @lua_type(ptr, i32)
declare void @lua_pushnil(ptr)
declare void @lua_pushvalue(ptr, i32)
@nupp.bytes.12 = private unnamed_addr constant [8 x i8] c"require\00", align 1
declare void @lua_getfield(ptr, i32, ptr)
@nupp.bytes.13 = private unnamed_addr constant [19 x i8] c"nupp.runtime.native", align 1
declare void @lua_call(ptr, i32, i32)
@nupp.bytes.14 = private unnamed_addr constant [11 x i8] c"aotRuntime\00", align 1
declare ptr @lua_tolstring(ptr, i32, ptr)
@nupp.bytes.15 = private unnamed_addr constant [56 x i8] c"AOT runtime is not the one this module was compiled for\00", align 1
@nupp.bytes.16 = private unnamed_addr constant [13 x i8] c"normalizeImpl", align 1
declare void @lua_pushcclosure(ptr, ptr, i32)
declare void @lua_rawset(ptr, i32)

define internal i32 @ks_a5aec1231ee04251_normalize_impl__neon_lua(ptr %L) #0 !dbg !5 {
entry:
  %slot6 = alloca i64, align 8
  %slot11 = alloca i1, align 4
  %slot41 = alloca double, align 8
  %slot46 = alloca i32, align 4
  %slot47 = alloca double, align 8
  %slot56 = alloca double, align 8
  %slot60 = alloca double, align 8
  %slot72 = alloca i1, align 4
  %slot88 = alloca double, align 8
  %slot89 = alloca double, align 8
  %slot96 = alloca double, align 8
  %slot100 = alloca double, align 8
  %slot112 = alloca double, align 8
  %slot125 = alloca double, align 8
  %slot147 = alloca double, align 8
  %slot161 = alloca double, align 8
  %slot162 = alloca i1, align 4
  %slot172 = alloca double, align 8
  %slot205 = alloca double, align 8
  %slot215 = alloca double, align 8
  %slot229 = alloca double, align 8
  %slot257 = alloca i1, align 4
  %slot264 = alloca i1, align 4
  %slot282 = alloca double, align 8
  %slot306 = alloca double, align 8
  %slot325 = alloca [8256 x i8], align 16
  %slot330 = alloca double, align 8
  %slot338 = alloca double, align 8
  %slot354 = alloca i1, align 4
  %slot356 = alloca double, align 8
  %slot359 = alloca double, align 8
  %slot362 = alloca double, align 8
  %slot368 = alloca double, align 8
  %slot377 = alloca double, align 8
  %slot387 = alloca double, align 8
  br label %body
body:
  %t1 = load ptr, ptr @ks.rt, !dbg !6
  %t2 = call i32 @lua_checkstack(ptr %L, i32 6), !dbg !6
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
  %t9 = call i32 @lua_toboolean(ptr %L, i32 2), !dbg !6
  %t10 = icmp ne i32 %t9, 0, !dbg !6
  store i1 %t10, ptr %slot11, !dbg !6
  %t12 = call i32 @lua_gettop(ptr %L), !dbg !6
  %t13 = add i32 %t12, 1, !dbg !6
  call void @lua_settop(ptr %L, i32 %t13), !dbg !6
  %t14 = add i32 %t12, 1, !dbg !6
  %t15 = call i32 @lua_checkstack(ptr %L, i32 3), !dbg !9
  %t16 = icmp eq i32 %t15, 0, !dbg !9
  br i1 %t16, label %lua.raise.3, label %lua.ok.4, !prof !7, !dbg !9
lua.raise.3:
  %t17 = getelementptr inbounds ptr, ptr %t1, i64 11, !dbg !9
  %rt.raise.18 = load ptr, ptr %t17, !invariant.load !8, !dbg !9
  call void %rt.raise.18(ptr %L, i64 1) nomerge, !dbg !9
  unreachable, !dbg !9
lua.ok.4:
  %t19 = fcmp oge double 0x0000000000000000, 0.0, !dbg !9
  %t20 = fcmp ole double 0x0000000000000000, 2147483647.0, !dbg !9
  %t21 = and i1 %t19, %t20, !dbg !9
  %t22 = select i1 %t21, double 0x0000000000000000, double 0.0, !dbg !9
  %t23 = fptosi double %t22 to i32, !dbg !9
  %t24 = sitofp i32 %t23 to double, !dbg !9
  %t25 = fcmp oeq double %t24, 0x0000000000000000, !dbg !9
  %t26 = and i1 %t21, %t25, !dbg !9
  %t27 = xor i1 %t26, true, !dbg !9
  br i1 %t27, label %lua.raise.5, label %lua.ok.6, !prof !7, !dbg !9
lua.raise.5:
  %t28 = getelementptr inbounds ptr, ptr %t1, i64 12, !dbg !9
  %rt.raise_count.29 = load ptr, ptr %t28, !invariant.load !8, !dbg !9
  call void %rt.raise_count.29(ptr %L, ptr @nupp.bytes.1) nomerge, !dbg !9
  unreachable, !dbg !9
lua.ok.6:
  %t30 = fcmp oge double 0x0000000000000000, 0.0, !dbg !9
  %t31 = fcmp ole double 0x0000000000000000, 2147483647.0, !dbg !9
  %t32 = and i1 %t30, %t31, !dbg !9
  %t33 = select i1 %t32, double 0x0000000000000000, double 0.0, !dbg !9
  %t34 = fptosi double %t33 to i32, !dbg !9
  %t35 = sitofp i32 %t34 to double, !dbg !9
  %t36 = fcmp oeq double %t35, 0x0000000000000000, !dbg !9
  %t37 = and i1 %t32, %t36, !dbg !9
  %t38 = xor i1 %t37, true, !dbg !9
  br i1 %t38, label %lua.raise.7, label %lua.ok.8, !prof !7, !dbg !9
lua.raise.7:
  %t39 = getelementptr inbounds ptr, ptr %t1, i64 12, !dbg !9
  %rt.raise_count.40 = load ptr, ptr %t39, !invariant.load !8, !dbg !9
  call void %rt.raise_count.40(ptr %L, ptr @nupp.bytes.2) nomerge, !dbg !9
  unreachable, !dbg !9
lua.ok.8:
  call void @lua_createtable(ptr %L, i32 %t23, i32 %t34), !dbg !9
  call void @lua_replace(ptr %L, i32 %t14), !dbg !9
  store double 0x0000000000000000, ptr %slot41, !dbg !10
  %t42 = icmp ugt i64 %t8, 4294967295, !dbg !11
  br i1 %t42, label %lua.raise.9, label %lua.ok.10, !prof !7, !dbg !11
lua.raise.9:
  %t43 = getelementptr inbounds ptr, ptr %t1, i64 11, !dbg !11
  %rt.raise.44 = load ptr, ptr %t43, !invariant.load !8, !dbg !11
  call void %rt.raise.44(ptr %L, i64 2) nomerge, !dbg !11
  unreachable, !dbg !11
lua.ok.10:
  %t45 = trunc i64 %t8 to i32, !dbg !11
  store i32 %t45, ptr %slot46, !dbg !11
  store double 0x0000000000000000, ptr %slot47, !dbg !12
  %t48 = load i1, ptr %slot11, !dbg !13
  br i1 %t48, label %and.rhs.12, label %and.end.13, !dbg !13
and.rhs.12:
  %t49 = load i32, ptr %slot46, !dbg !13
  %t50 = uitofp i32 %t49 to double, !dbg !13
  %t51 = fcmp oge double %t50, 0x4000000000000000, !dbg !13
  br label %and.end.13, !dbg !13
and.end.13:
  %t52 = phi i1 [ false, %lua.ok.10 ], [ %t51, %and.rhs.12 ], !dbg !13
  br i1 %t52, label %if.then.14, label %if.else.15, !dbg !13
if.then.14:
  %t53 = getelementptr inbounds ptr, ptr %t1, i64 20, !dbg !14
  %rt.string_byte_lua.54 = load ptr, ptr %t53, !invariant.load !8, !dbg !14
  %t55 = call double %rt.string_byte_lua.54(ptr %L, ptr %t7, i64 %t8, double 0x3FF0000000000000), !dbg !14
  store double %t55, ptr %slot56, !dbg !14
  %t57 = getelementptr inbounds ptr, ptr %t1, i64 20, !dbg !15
  %rt.string_byte_lua.58 = load ptr, ptr %t57, !invariant.load !8, !dbg !15
  %t59 = call double %rt.string_byte_lua.58(ptr %L, ptr %t7, i64 %t8, double 0x4000000000000000), !dbg !15
  store double %t59, ptr %slot60, !dbg !15
  %t61 = load double, ptr %slot56, !dbg !16
  %t62 = fcmp oge double %t61, 0x4050400000000000, !dbg !16
  br i1 %t62, label %and.rhs.16, label %and.end.17, !dbg !16
and.rhs.16:
  %t63 = load double, ptr %slot56, !dbg !16
  %t64 = fcmp ole double %t63, 0x4056800000000000, !dbg !16
  br label %and.end.17, !dbg !16
and.end.17:
  %t65 = phi i1 [ false, %if.then.14 ], [ %t64, %and.rhs.16 ], !dbg !16
  br i1 %t65, label %or.end.19, label %or.rhs.18, !dbg !16
or.rhs.18:
  %t66 = load double, ptr %slot56, !dbg !16
  %t67 = fcmp oge double %t66, 0x4058400000000000, !dbg !16
  br i1 %t67, label %and.rhs.20, label %and.end.21, !dbg !16
and.rhs.20:
  %t68 = load double, ptr %slot56, !dbg !16
  %t69 = fcmp ole double %t68, 0x405E800000000000, !dbg !16
  br label %and.end.21, !dbg !16
and.end.21:
  %t70 = phi i1 [ false, %or.rhs.18 ], [ %t69, %and.rhs.20 ], !dbg !16
  br label %or.end.19, !dbg !16
or.end.19:
  %t71 = phi i1 [ true, %and.end.17 ], [ %t70, %and.end.21 ], !dbg !16
  store i1 %t71, ptr %slot72, !dbg !16
  %t73 = load i1, ptr %slot72, !dbg !17
  br i1 %t73, label %and.rhs.23, label %and.end.24, !dbg !17
and.rhs.23:
  %t74 = load double, ptr %slot60, !dbg !17
  %t75 = fcmp oeq double %t74, 0x404D000000000000, !dbg !17
  br label %and.end.24, !dbg !17
and.end.24:
  %t76 = phi i1 [ false, %or.end.19 ], [ %t75, %and.rhs.23 ], !dbg !17
  br i1 %t76, label %if.then.25, label %if.else.26, !dbg !17
if.then.25:
  store double 0x4000000000000000, ptr %slot47, !dbg !18
  br label %if.end.22, !dbg !18
if.else.26:
  %t77 = load double, ptr %slot56, !dbg !18
  %t78 = fcmp oeq double %t77, 0x4047800000000000, !dbg !18
  br i1 %t78, label %or.end.28, label %or.rhs.27, !dbg !18
or.rhs.27:
  %t79 = load double, ptr %slot56, !dbg !18
  %t80 = fcmp oeq double %t79, 0x4057000000000000, !dbg !18
  br label %or.end.28, !dbg !18
or.end.28:
  %t81 = phi i1 [ true, %if.else.26 ], [ %t80, %or.rhs.27 ], !dbg !18
  br i1 %t81, label %and.rhs.29, label %and.end.30, !dbg !18
and.rhs.29:
  %t82 = load double, ptr %slot60, !dbg !18
  %t83 = fcmp oeq double %t82, 0x4047800000000000, !dbg !18
  br i1 %t83, label %or.end.32, label %or.rhs.31, !dbg !18
or.rhs.31:
  %t84 = load double, ptr %slot60, !dbg !18
  %t85 = fcmp oeq double %t84, 0x4057000000000000, !dbg !18
  br label %or.end.32, !dbg !18
or.end.32:
  %t86 = phi i1 [ true, %and.rhs.29 ], [ %t85, %or.rhs.31 ], !dbg !18
  br label %and.end.30, !dbg !18
and.end.30:
  %t87 = phi i1 [ false, %or.end.28 ], [ %t86, %or.end.32 ], !dbg !18
  br i1 %t87, label %if.then.33, label %if.else.34, !dbg !18
if.then.33:
  store double 0x4000000000000000, ptr %slot88, !dbg !19
  store double 0x4000000000000000, ptr %slot89, !dbg !20
  %t90 = load i32, ptr %slot46, !dbg !21
  %t91 = uitofp i32 %t90 to double, !dbg !21
  %t92 = fcmp oge double %t91, 0x4010000000000000, !dbg !21
  br i1 %t92, label %if.then.36, label %if.else.37, !dbg !21
if.then.36:
  %t93 = getelementptr inbounds ptr, ptr %t1, i64 20, !dbg !22
  %rt.string_byte_lua.94 = load ptr, ptr %t93, !invariant.load !8, !dbg !22
  %t95 = call double %rt.string_byte_lua.94(ptr %L, ptr %t7, i64 %t8, double 0x4008000000000000), !dbg !22
  store double %t95, ptr %slot96, !dbg !22
  %t97 = getelementptr inbounds ptr, ptr %t1, i64 20, !dbg !23
  %rt.string_byte_lua.98 = load ptr, ptr %t97, !invariant.load !8, !dbg !23
  %t99 = call double %rt.string_byte_lua.98(ptr %L, ptr %t7, i64 %t8, double 0x4010000000000000), !dbg !23
  store double %t99, ptr %slot100, !dbg !23
  %t101 = load double, ptr %slot96, !dbg !24
  %t102 = fcmp oeq double %t101, 0x404F800000000000, !dbg !24
  br i1 %t102, label %or.end.40, label %or.rhs.39, !dbg !24
or.rhs.39:
  %t103 = load double, ptr %slot96, !dbg !24
  %t104 = fcmp oeq double %t103, 0x4047000000000000, !dbg !24
  br label %or.end.40, !dbg !24
or.end.40:
  %t105 = phi i1 [ true, %if.then.36 ], [ %t104, %or.rhs.39 ], !dbg !24
  br i1 %t105, label %and.rhs.41, label %and.end.42, !dbg !24
and.rhs.41:
  %t106 = load double, ptr %slot100, !dbg !24
  %t107 = fcmp oeq double %t106, 0x4047800000000000, !dbg !24
  br i1 %t107, label %or.end.44, label %or.rhs.43, !dbg !24
or.rhs.43:
  %t108 = load double, ptr %slot100, !dbg !24
  %t109 = fcmp oeq double %t108, 0x4057000000000000, !dbg !24
  br label %or.end.44, !dbg !24
or.end.44:
  %t110 = phi i1 [ true, %and.rhs.41 ], [ %t109, %or.rhs.43 ], !dbg !24
  br label %and.end.42, !dbg !24
and.end.42:
  %t111 = phi i1 [ false, %or.end.40 ], [ %t110, %or.end.44 ], !dbg !24
  br i1 %t111, label %if.then.45, label %if.else.46, !dbg !24
if.then.45:
  store double 0x3FF0000000000000, ptr %slot89, !dbg !25
  br label %if.end.38, !dbg !25
if.else.46:
  br label %if.end.38, !dbg !25
if.end.38:
  br label %if.end.35, !dbg !25
if.else.37:
  br label %if.end.35, !dbg !25
if.end.35:
  store double 0x0000000000000000, ptr %slot112, !dbg !26
  br label %while.head.47, !dbg !27
while.head.47:
  %t113 = load double, ptr %slot112, !dbg !27
  %t114 = load double, ptr %slot89, !dbg !27
  %t115 = fcmp olt double %t113, %t114, !dbg !27
  br i1 %t115, label %while.body.48, label %while.end.49, !dbg !27
while.body.48:
  br label %while.head.50, !dbg !28
while.head.50:
  %t116 = load double, ptr %slot88, !dbg !28
  %t117 = load i32, ptr %slot46, !dbg !28
  %t118 = uitofp i32 %t117 to double, !dbg !28
  %t119 = fcmp olt double %t116, %t118, !dbg !28
  br i1 %t119, label %while.body.51, label %while.end.52, !dbg !28
while.body.51:
  %t120 = load double, ptr %slot88, !dbg !29
  %t121 = fadd double %t120, 0x3FF0000000000000, !dbg !29
  %t122 = getelementptr inbounds ptr, ptr %t1, i64 20, !dbg !29
  %rt.string_byte_lua.123 = load ptr, ptr %t122, !invariant.load !8, !dbg !29
  %t124 = call double %rt.string_byte_lua.123(ptr %L, ptr %t7, i64 %t8, double %t121), !dbg !29
  store double %t124, ptr %slot125, !dbg !29
  %t126 = load double, ptr %slot125, !dbg !30
  %t127 = fcmp oeq double %t126, 0x4047800000000000, !dbg !30
  br i1 %t127, label %or.end.55, label %or.rhs.54, !dbg !30
or.rhs.54:
  %t128 = load double, ptr %slot125, !dbg !30
  %t129 = fcmp oeq double %t128, 0x4057000000000000, !dbg !30
  br label %or.end.55, !dbg !30
or.end.55:
  %t130 = phi i1 [ true, %while.body.51 ], [ %t129, %or.rhs.54 ], !dbg !30
  br i1 %t130, label %if.then.56, label %if.else.57, !dbg !30
if.then.56:
  br label %while.end.52, !dbg !31
if.else.57:
  br label %if.end.53, !dbg !31
if.end.53:
  %t131 = load double, ptr %slot88, !dbg !32
  %t132 = fadd double %t131, 0x3FF0000000000000, !dbg !32
  store double %t132, ptr %slot88, !dbg !32
  br label %while.head.50, !dbg !32
while.end.52:
  %t133 = load double, ptr %slot112, !dbg !33
  %t134 = fadd double %t133, 0x3FF0000000000000, !dbg !33
  store double %t134, ptr %slot112, !dbg !33
  %t135 = load double, ptr %slot112, !dbg !34
  %t136 = load double, ptr %slot89, !dbg !34
  %t137 = fcmp olt double %t135, %t136, !dbg !34
  br i1 %t137, label %if.then.59, label %if.else.60, !dbg !34
if.then.59:
  br label %while.head.61, !dbg !35
while.head.61:
  %t138 = load double, ptr %slot88, !dbg !35
  %t139 = load i32, ptr %slot46, !dbg !35
  %t140 = uitofp i32 %t139 to double, !dbg !35
  %t141 = fcmp olt double %t138, %t140, !dbg !35
  br i1 %t141, label %while.body.62, label %while.end.63, !dbg !35
while.body.62:
  %t142 = load double, ptr %slot88, !dbg !36
  %t143 = fadd double %t142, 0x3FF0000000000000, !dbg !36
  %t144 = getelementptr inbounds ptr, ptr %t1, i64 20, !dbg !36
  %rt.string_byte_lua.145 = load ptr, ptr %t144, !invariant.load !8, !dbg !36
  %t146 = call double %rt.string_byte_lua.145(ptr %L, ptr %t7, i64 %t8, double %t143), !dbg !36
  store double %t146, ptr %slot147, !dbg !36
  %t148 = load double, ptr %slot147, !dbg !37
  %t149 = fcmp une double %t148, 0x4047800000000000, !dbg !37
  br i1 %t149, label %and.rhs.65, label %and.end.66, !dbg !37
and.rhs.65:
  %t150 = load double, ptr %slot147, !dbg !37
  %t151 = fcmp une double %t150, 0x4057000000000000, !dbg !37
  br label %and.end.66, !dbg !37
and.end.66:
  %t152 = phi i1 [ false, %while.body.62 ], [ %t151, %and.rhs.65 ], !dbg !37
  br i1 %t152, label %if.then.67, label %if.else.68, !dbg !37
if.then.67:
  br label %while.end.63, !dbg !38
if.else.68:
  br label %if.end.64, !dbg !38
if.end.64:
  %t153 = load double, ptr %slot88, !dbg !39
  %t154 = fadd double %t153, 0x3FF0000000000000, !dbg !39
  store double %t154, ptr %slot88, !dbg !39
  br label %while.head.61, !dbg !39
while.end.63:
  %t155 = load double, ptr %slot88, !dbg !40
  %t156 = load i32, ptr %slot46, !dbg !40
  %t157 = uitofp i32 %t156 to double, !dbg !40
  %t158 = fcmp oeq double %t155, %t157, !dbg !40
  br i1 %t158, label %if.then.70, label %if.else.71, !dbg !40
if.then.70:
  br label %while.end.49, !dbg !41
if.else.71:
  br label %if.end.69, !dbg !41
if.end.69:
  br label %if.end.58, !dbg !41
if.else.60:
  br label %if.end.58, !dbg !41
if.end.58:
  br label %while.head.47, !dbg !41
while.end.49:
  %t159 = load double, ptr %slot88, !dbg !42
  store double %t159, ptr %slot47, !dbg !42
  br label %if.end.22, !dbg !42
if.else.34:
  br label %if.end.22, !dbg !42
if.end.22:
  br label %if.end.11, !dbg !42
if.else.15:
  br label %if.end.11, !dbg !42
if.end.11:
  %t160 = load double, ptr %slot47, !dbg !43
  store double %t160, ptr %slot161, !dbg !43
  store i1 false, ptr %slot162, !dbg !44
  %t163 = load double, ptr %slot161, !dbg !45
  %t164 = load i32, ptr %slot46, !dbg !45
  %t165 = uitofp i32 %t164 to double, !dbg !45
  %t166 = fcmp olt double %t163, %t165, !dbg !45
  br i1 %t166, label %if.then.73, label %if.else.74, !dbg !45
if.then.73:
  %t167 = load double, ptr %slot161, !dbg !46
  %t168 = fadd double %t167, 0x3FF0000000000000, !dbg !46
  %t169 = getelementptr inbounds ptr, ptr %t1, i64 20, !dbg !46
  %rt.string_byte_lua.170 = load ptr, ptr %t169, !invariant.load !8, !dbg !46
  %t171 = call double %rt.string_byte_lua.170(ptr %L, ptr %t7, i64 %t8, double %t168), !dbg !46
  store double %t171, ptr %slot172, !dbg !46
  %t173 = load double, ptr %slot172, !dbg !47
  %t174 = fcmp oeq double %t173, 0x4047800000000000, !dbg !47
  br i1 %t174, label %or.end.77, label %or.rhs.76, !dbg !47
or.rhs.76:
  %t175 = load i1, ptr %slot11, !dbg !47
  br i1 %t175, label %and.rhs.78, label %and.end.79, !dbg !47
and.rhs.78:
  %t176 = load double, ptr %slot172, !dbg !47
  %t177 = fcmp oeq double %t176, 0x4057000000000000, !dbg !47
  br label %and.end.79, !dbg !47
and.end.79:
  %t178 = phi i1 [ false, %or.rhs.76 ], [ %t177, %and.rhs.78 ], !dbg !47
  br label %or.end.77, !dbg !47
or.end.77:
  %t179 = phi i1 [ true, %if.then.73 ], [ %t178, %and.end.79 ], !dbg !47
  br i1 %t179, label %if.then.80, label %if.else.81, !dbg !47
if.then.80:
  store i1 true, ptr %slot162, !dbg !48
  br label %while.head.82, !dbg !49
while.head.82:
  %t180 = load double, ptr %slot161, !dbg !49
  %t181 = load i32, ptr %slot46, !dbg !49
  %t182 = uitofp i32 %t181 to double, !dbg !49
  %t183 = fcmp olt double %t180, %t182, !dbg !49
  br i1 %t183, label %while.body.83, label %while.end.84, !dbg !49
while.body.83:
  %t184 = load double, ptr %slot161, !dbg !50
  %t185 = fadd double %t184, 0x3FF0000000000000, !dbg !50
  %t186 = getelementptr inbounds ptr, ptr %t1, i64 20, !dbg !50
  %rt.string_byte_lua.187 = load ptr, ptr %t186, !invariant.load !8, !dbg !50
  %t188 = call double %rt.string_byte_lua.187(ptr %L, ptr %t7, i64 %t8, double %t185), !dbg !50
  store double %t188, ptr %slot172, !dbg !50
  %t189 = load double, ptr %slot172, !dbg !51
  %t190 = fcmp une double %t189, 0x4047800000000000, !dbg !51
  br i1 %t190, label %and.rhs.86, label %and.end.87, !dbg !51
and.rhs.86:
  %t191 = load i1, ptr %slot11, !dbg !51
  %t192 = xor i1 %t191, true, !dbg !51
  br i1 %t192, label %or.end.89, label %or.rhs.88, !dbg !51
or.rhs.88:
  %t193 = load double, ptr %slot172, !dbg !51
  %t194 = fcmp une double %t193, 0x4057000000000000, !dbg !51
  br label %or.end.89, !dbg !51
or.end.89:
  %t195 = phi i1 [ true, %and.rhs.86 ], [ %t194, %or.rhs.88 ], !dbg !51
  br label %and.end.87, !dbg !51
and.end.87:
  %t196 = phi i1 [ false, %while.body.83 ], [ %t195, %or.end.89 ], !dbg !51
  br i1 %t196, label %if.then.90, label %if.else.91, !dbg !51
if.then.90:
  br label %while.end.84, !dbg !52
if.else.91:
  br label %if.end.85, !dbg !52
if.end.85:
  %t197 = load double, ptr %slot161, !dbg !53
  %t198 = fadd double %t197, 0x3FF0000000000000, !dbg !53
  store double %t198, ptr %slot161, !dbg !53
  br label %while.head.82, !dbg !53
while.end.84:
  br label %if.end.75, !dbg !53
if.else.81:
  br label %if.end.75, !dbg !53
if.end.75:
  br label %if.end.72, !dbg !53
if.else.74:
  br label %if.end.72, !dbg !53
if.end.72:
  br label %while.head.92, !dbg !54
while.head.92:
  %t199 = load double, ptr %slot161, !dbg !54
  %t200 = load i32, ptr %slot46, !dbg !54
  %t201 = uitofp i32 %t200 to double, !dbg !54
  %t202 = fcmp olt double %t199, %t201, !dbg !54
  br i1 %t202, label %while.body.93, label %while.end.94, !dbg !54
while.body.93:
  %t203 = load double, ptr %slot161, !dbg !55
  %t204 = fadd double %t203, 0x3FF0000000000000, !dbg !55
  store double %t204, ptr %slot205, !dbg !55
  br label %while.head.95, !dbg !56
while.head.95:
  %t206 = load double, ptr %slot161, !dbg !56
  %t207 = load i32, ptr %slot46, !dbg !56
  %t208 = uitofp i32 %t207 to double, !dbg !56
  %t209 = fcmp olt double %t206, %t208, !dbg !56
  br i1 %t209, label %while.body.96, label %while.end.97, !dbg !56
while.body.96:
  %t210 = load double, ptr %slot161, !dbg !57
  %t211 = fadd double %t210, 0x3FF0000000000000, !dbg !57
  %t212 = getelementptr inbounds ptr, ptr %t1, i64 20, !dbg !57
  %rt.string_byte_lua.213 = load ptr, ptr %t212, !invariant.load !8, !dbg !57
  %t214 = call double %rt.string_byte_lua.213(ptr %L, ptr %t7, i64 %t8, double %t211), !dbg !57
  store double %t214, ptr %slot215, !dbg !57
  %t216 = load double, ptr %slot215, !dbg !58
  %t217 = fcmp oeq double %t216, 0x4047800000000000, !dbg !58
  br i1 %t217, label %or.end.100, label %or.rhs.99, !dbg !58
or.rhs.99:
  %t218 = load i1, ptr %slot11, !dbg !58
  br i1 %t218, label %and.rhs.101, label %and.end.102, !dbg !58
and.rhs.101:
  %t219 = load double, ptr %slot215, !dbg !58
  %t220 = fcmp oeq double %t219, 0x4057000000000000, !dbg !58
  br label %and.end.102, !dbg !58
and.end.102:
  %t221 = phi i1 [ false, %or.rhs.99 ], [ %t220, %and.rhs.101 ], !dbg !58
  br label %or.end.100, !dbg !58
or.end.100:
  %t222 = phi i1 [ true, %while.body.96 ], [ %t221, %and.end.102 ], !dbg !58
  br i1 %t222, label %if.then.103, label %if.else.104, !dbg !58
if.then.103:
  br label %while.end.97, !dbg !59
if.else.104:
  br label %if.end.98, !dbg !59
if.end.98:
  %t223 = load double, ptr %slot161, !dbg !60
  %t224 = fadd double %t223, 0x3FF0000000000000, !dbg !60
  store double %t224, ptr %slot161, !dbg !60
  br label %while.head.95, !dbg !60
while.end.97:
  %t225 = load double, ptr %slot161, !dbg !61
  %t226 = load double, ptr %slot205, !dbg !61
  %t227 = fsub double %t225, %t226, !dbg !61
  %t228 = fadd double %t227, 0x3FF0000000000000, !dbg !61
  store double %t228, ptr %slot229, !dbg !61
  %t230 = load double, ptr %slot229, !dbg !62
  %t231 = fcmp une double %t230, 0x0000000000000000, !dbg !62
  br i1 %t231, label %and.rhs.106, label %and.end.107, !dbg !62
and.rhs.106:
  %t232 = load double, ptr %slot229, !dbg !62
  %t233 = fcmp oeq double %t232, 0x3FF0000000000000, !dbg !62
  br i1 %t233, label %and.rhs.108, label %and.end.109, !dbg !62
and.rhs.108:
  %t234 = load double, ptr %slot205, !dbg !62
  %t235 = getelementptr inbounds ptr, ptr %t1, i64 20, !dbg !62
  %rt.string_byte_lua.236 = load ptr, ptr %t235, !invariant.load !8, !dbg !62
  %t237 = call double %rt.string_byte_lua.236(ptr %L, ptr %t7, i64 %t8, double %t234), !dbg !62
  %t238 = fcmp oeq double %t237, 0x4047000000000000, !dbg !62
  br label %and.end.109, !dbg !62
and.end.109:
  %t239 = phi i1 [ false, %and.rhs.106 ], [ %t238, %and.rhs.108 ], !dbg !62
  %t240 = xor i1 %t239, true, !dbg !62
  br label %and.end.107, !dbg !62
and.end.107:
  %t241 = phi i1 [ false, %while.end.97 ], [ %t240, %and.end.109 ], !dbg !62
  br i1 %t241, label %if.then.110, label %if.else.111, !dbg !62
if.then.110:
  %t242 = load double, ptr %slot229, !dbg !63
  %t243 = fcmp oeq double %t242, 0x4000000000000000, !dbg !63
  br i1 %t243, label %and.rhs.112, label %and.end.113, !dbg !63
and.rhs.112:
  %t244 = load double, ptr %slot205, !dbg !63
  %t245 = getelementptr inbounds ptr, ptr %t1, i64 20, !dbg !63
  %rt.string_byte_lua.246 = load ptr, ptr %t245, !invariant.load !8, !dbg !63
  %t247 = call double %rt.string_byte_lua.246(ptr %L, ptr %t7, i64 %t8, double %t244), !dbg !63
  %t248 = fcmp oeq double %t247, 0x4047000000000000, !dbg !63
  br label %and.end.113, !dbg !63
and.end.113:
  %t249 = phi i1 [ false, %if.then.110 ], [ %t248, %and.rhs.112 ], !dbg !63
  br i1 %t249, label %and.rhs.114, label %and.end.115, !dbg !63
and.rhs.114:
  %t250 = load double, ptr %slot205, !dbg !63
  %t251 = fadd double %t250, 0x3FF0000000000000, !dbg !63
  %t252 = getelementptr inbounds ptr, ptr %t1, i64 20, !dbg !63
  %rt.string_byte_lua.253 = load ptr, ptr %t252, !invariant.load !8, !dbg !63
  %t254 = call double %rt.string_byte_lua.253(ptr %L, ptr %t7, i64 %t8, double %t251), !dbg !63
  %t255 = fcmp oeq double %t254, 0x4047000000000000, !dbg !63
  br label %and.end.115, !dbg !63
and.end.115:
  %t256 = phi i1 [ false, %and.end.113 ], [ %t255, %and.rhs.114 ], !dbg !63
  store i1 %t256, ptr %slot257, !dbg !63
  %t258 = load i1, ptr %slot257, !dbg !64
  br i1 %t258, label %and.rhs.116, label %and.end.117, !dbg !64
and.rhs.116:
  %t259 = load i1, ptr %slot162, !dbg !64
  br label %and.end.117, !dbg !64
and.end.117:
  %t260 = phi i1 [ false, %and.end.115 ], [ %t259, %and.rhs.116 ], !dbg !64
  br i1 %t260, label %and.rhs.118, label %and.end.119, !dbg !64
and.rhs.118:
  %t261 = load double, ptr %slot41, !dbg !64
  %t262 = fcmp oeq double %t261, 0x0000000000000000, !dbg !64
  br label %and.end.119, !dbg !64
and.end.119:
  %t263 = phi i1 [ false, %and.end.117 ], [ %t262, %and.rhs.118 ], !dbg !64
  store i1 %t263, ptr %slot264, !dbg !64
  %t265 = load i1, ptr %slot257, !dbg !65
  br i1 %t265, label %and.rhs.121, label %and.end.122, !dbg !65
and.rhs.121:
  %t266 = load double, ptr %slot41, !dbg !65
  %t267 = fcmp ogt double %t266, 0x0000000000000000, !dbg !65
  br label %and.end.122, !dbg !65
and.end.122:
  %t268 = phi i1 [ false, %and.end.119 ], [ %t267, %and.rhs.121 ], !dbg !65
  br i1 %t268, label %if.then.123, label %if.else.124, !dbg !65
if.then.123:
  %t269 = sext i32 %t14 to i64, !dbg !66
  %t270 = load double, ptr %slot41, !dbg !66
  %t271 = getelementptr inbounds ptr, ptr %t1, i64 23, !dbg !66
  %rt.table_number.272 = load ptr, ptr %t271, !invariant.load !8, !dbg !66
  %t273 = call double %rt.table_number.272(ptr %L, i64 %t269, double %t270, ptr @nupp.bytes.3), !dbg !66
  %t274 = fcmp ogt double %t273, 0x0000000000000000, !dbg !66
  br i1 %t274, label %if.then.126, label %if.else.127, !dbg !66
if.then.126:
  %t275 = load double, ptr %slot41, !dbg !67
  %t276 = fsub double %t275, 0x3FF0000000000000, !dbg !67
  store double %t276, ptr %slot41, !dbg !67
  store i1 true, ptr %slot264, !dbg !68
  br label %if.end.125, !dbg !68
if.else.127:
  br label %if.end.125, !dbg !68
if.end.125:
  br label %if.end.120, !dbg !68
if.else.124:
  br label %if.end.120, !dbg !68
if.end.120:
  %t277 = load i1, ptr %slot264, !dbg !69
  %t278 = xor i1 %t277, true, !dbg !69
  br i1 %t278, label %if.then.129, label %if.else.130, !dbg !69
if.then.129:
  %t279 = load double, ptr %slot41, !dbg !70
  %t280 = fadd double %t279, 0x3FF0000000000000, !dbg !70
  store double %t280, ptr %slot41, !dbg !70
  %t281 = load double, ptr %slot205, !dbg !71
  store double %t281, ptr %slot282, !dbg !71
  %t283 = load i1, ptr %slot257, !dbg !72
  br i1 %t283, label %if.then.132, label %if.else.133, !dbg !72
if.then.132:
  store double 0x0000000000000000, ptr %slot282, !dbg !73
  br label %if.end.131, !dbg !73
if.else.133:
  br label %if.end.131, !dbg !73
if.end.131:
  %t284 = load double, ptr %slot282, !dbg !74
  call void @lua_pushnumber(ptr %L, double %t284), !dbg !74
  %t285 = load double, ptr %slot41, !dbg !74
  %t286 = fcmp oge double %t285, 1.0, !dbg !74
  %t287 = fcmp ole double %t285, 2147483647.0, !dbg !74
  %t288 = and i1 %t286, %t287, !dbg !74
  %t289 = select i1 %t288, double %t285, double 0.0, !dbg !74
  %t290 = fptosi double %t289 to i32, !dbg !74
  %t291 = sitofp i32 %t290 to double, !dbg !74
  %t292 = fcmp oeq double %t291, %t285, !dbg !74
  %t293 = and i1 %t288, %t292, !dbg !74
  %t294 = xor i1 %t293, true, !dbg !74
  br i1 %t294, label %lua.raise.134, label %lua.ok.135, !prof !7, !dbg !74
lua.raise.134:
  %t295 = getelementptr inbounds ptr, ptr %t1, i64 13, !dbg !74
  %rt.raise_index.296 = load ptr, ptr %t295, !invariant.load !8, !dbg !74
  call void %rt.raise_index.296(ptr %L, ptr @nupp.bytes.4) nomerge, !dbg !74
  unreachable, !dbg !74
lua.ok.135:
  call void @lua_rawseti(ptr %L, i32 %t14, i32 %t290), !dbg !74
  br label %if.end.128, !dbg !74
if.else.130:
  br label %if.end.128, !dbg !74
if.end.128:
  br label %if.end.105, !dbg !74
if.else.111:
  br label %if.end.105, !dbg !74
if.end.105:
  br label %while.head.136, !dbg !75
while.head.136:
  %t297 = load double, ptr %slot161, !dbg !75
  %t298 = load i32, ptr %slot46, !dbg !75
  %t299 = uitofp i32 %t298 to double, !dbg !75
  %t300 = fcmp olt double %t297, %t299, !dbg !75
  br i1 %t300, label %while.body.137, label %while.end.138, !dbg !75
while.body.137:
  %t301 = load double, ptr %slot161, !dbg !76
  %t302 = fadd double %t301, 0x3FF0000000000000, !dbg !76
  %t303 = getelementptr inbounds ptr, ptr %t1, i64 20, !dbg !76
  %rt.string_byte_lua.304 = load ptr, ptr %t303, !invariant.load !8, !dbg !76
  %t305 = call double %rt.string_byte_lua.304(ptr %L, ptr %t7, i64 %t8, double %t302), !dbg !76
  store double %t305, ptr %slot306, !dbg !76
  %t307 = load double, ptr %slot306, !dbg !77
  %t308 = fcmp une double %t307, 0x4047800000000000, !dbg !77
  br i1 %t308, label %and.rhs.140, label %and.end.141, !dbg !77
and.rhs.140:
  %t309 = load i1, ptr %slot11, !dbg !77
  %t310 = xor i1 %t309, true, !dbg !77
  br i1 %t310, label %or.end.143, label %or.rhs.142, !dbg !77
or.rhs.142:
  %t311 = load double, ptr %slot306, !dbg !77
  %t312 = fcmp une double %t311, 0x4057000000000000, !dbg !77
  br label %or.end.143, !dbg !77
or.end.143:
  %t313 = phi i1 [ true, %and.rhs.140 ], [ %t312, %or.rhs.142 ], !dbg !77
  br label %and.end.141, !dbg !77
and.end.141:
  %t314 = phi i1 [ false, %while.body.137 ], [ %t313, %or.end.143 ], !dbg !77
  br i1 %t314, label %if.then.144, label %if.else.145, !dbg !77
if.then.144:
  br label %while.end.138, !dbg !78
if.else.145:
  br label %if.end.139, !dbg !78
if.end.139:
  %t315 = load double, ptr %slot161, !dbg !79
  %t316 = fadd double %t315, 0x3FF0000000000000, !dbg !79
  store double %t316, ptr %slot161, !dbg !79
  br label %while.head.136, !dbg !79
while.end.138:
  br label %while.head.92, !dbg !79
while.end.94:
  %t317 = load double, ptr %slot41, !dbg !80
  %t318 = fcmp oeq double %t317, 0x0000000000000000, !dbg !80
  br i1 %t318, label %and.rhs.147, label %and.end.148, !dbg !80
and.rhs.147:
  %t319 = load double, ptr %slot47, !dbg !80
  %t320 = fcmp oeq double %t319, 0x0000000000000000, !dbg !80
  br label %and.end.148, !dbg !80
and.end.148:
  %t321 = phi i1 [ false, %while.end.94 ], [ %t320, %and.rhs.147 ], !dbg !80
  br i1 %t321, label %and.rhs.149, label %and.end.150, !dbg !80
and.rhs.149:
  %t322 = load i1, ptr %slot162, !dbg !80
  %t323 = xor i1 %t322, true, !dbg !80
  br label %and.end.150, !dbg !80
and.end.150:
  %t324 = phi i1 [ false, %and.end.148 ], [ %t323, %and.rhs.149 ], !dbg !80
  br i1 %t324, label %if.then.151, label %if.else.152, !dbg !80
if.then.151:
  call void @lua_pushlstring(ptr %L, ptr @nupp.bytes.5, i64 1), !dbg !81
  ret i32 1, !dbg !81
if.else.152:
  br label %if.end.146, !dbg !81
if.end.146:
  %t326 = getelementptr inbounds ptr, ptr %t1, i64 24, !dbg !82
  %rt.string_buffer_init.327 = load ptr, ptr %t326, !invariant.load !8, !dbg !82
  call void %rt.string_buffer_init.327(ptr %L, ptr %slot325), !dbg !82
  %t328 = getelementptr inbounds ptr, ptr %t1, i64 25, !dbg !82
  %rt.string_buffer_append.329 = load ptr, ptr %t328, !invariant.load !8, !dbg !82
  call void %rt.string_buffer_append.329(ptr %L, ptr %slot325, ptr @nupp.bytes.6, i64 0), !dbg !82
  store double 0x3FF0000000000000, ptr %slot330, !dbg !83
  br label %while.head.153, !dbg !84
while.head.153:
  %t331 = load double, ptr %slot330, !dbg !84
  %t332 = load double, ptr %slot47, !dbg !84
  %t333 = fcmp ole double %t331, %t332, !dbg !84
  br i1 %t333, label %while.body.154, label %while.end.155, !dbg !84
while.body.154:
  %t334 = load double, ptr %slot330, !dbg !85
  %t335 = getelementptr inbounds ptr, ptr %t1, i64 20, !dbg !85
  %rt.string_byte_lua.336 = load ptr, ptr %t335, !invariant.load !8, !dbg !85
  %t337 = call double %rt.string_byte_lua.336(ptr %L, ptr %t7, i64 %t8, double %t334), !dbg !85
  store double %t337, ptr %slot338, !dbg !85
  %t339 = load i1, ptr %slot11, !dbg !86
  br i1 %t339, label %and.rhs.157, label %and.end.158, !dbg !86
and.rhs.157:
  %t340 = load double, ptr %slot338, !dbg !86
  %t341 = fcmp oeq double %t340, 0x4057000000000000, !dbg !86
  br label %and.end.158, !dbg !86
and.end.158:
  %t342 = phi i1 [ false, %while.body.154 ], [ %t341, %and.rhs.157 ], !dbg !86
  br i1 %t342, label %if.then.159, label %if.else.160, !dbg !86
if.then.159:
  %t343 = getelementptr inbounds ptr, ptr %t1, i64 25, !dbg !87
  %rt.string_buffer_append.344 = load ptr, ptr %t343, !invariant.load !8, !dbg !87
  call void %rt.string_buffer_append.344(ptr %L, ptr %slot325, ptr @nupp.bytes.7, i64 1), !dbg !87
  br label %if.end.156, !dbg !87
if.else.160:
  %t345 = load double, ptr %slot330, !dbg !88
  %t346 = load double, ptr %slot330, !dbg !88
  %t347 = getelementptr inbounds ptr, ptr %t1, i64 26, !dbg !88
  %rt.string_buffer_append_slice.348 = load ptr, ptr %t347, !invariant.load !8, !dbg !88
  call void %rt.string_buffer_append_slice.348(ptr %L, ptr %slot325, ptr %t7, i64 %t8, double %t345, double %t346), !dbg !88
  br label %if.end.156, !dbg !88
if.end.156:
  %t349 = load double, ptr %slot330, !dbg !89
  %t350 = fadd double %t349, 0x3FF0000000000000, !dbg !89
  store double %t350, ptr %slot330, !dbg !89
  br label %while.head.153, !dbg !89
while.end.155:
  %t351 = load i1, ptr %slot162, !dbg !90
  br i1 %t351, label %if.then.162, label %if.else.163, !dbg !90
if.then.162:
  %t352 = getelementptr inbounds ptr, ptr %t1, i64 25, !dbg !91
  %rt.string_buffer_append.353 = load ptr, ptr %t352, !invariant.load !8, !dbg !91
  call void %rt.string_buffer_append.353(ptr %L, ptr %slot325, ptr @nupp.bytes.7, i64 1), !dbg !91
  br label %if.end.161, !dbg !91
if.else.163:
  br label %if.end.161, !dbg !91
if.end.161:
  store i1 false, ptr %slot354, !dbg !92
  %t355 = load double, ptr %slot41, !dbg !93
  store double %t355, ptr %slot356, !dbg !93
  %t357 = sitofp i32 1 to double, !dbg !94
  %t358 = load double, ptr %slot356, !dbg !94
  store double %t357, ptr %slot359, !dbg !94
  br label %for.head.164, !dbg !94
for.head.164:
  %t360 = load double, ptr %slot359, !dbg !94
  %t361 = fcmp ole double %t360, %t358, !dbg !94
  br i1 %t361, label %for.body.165, label %for.end.167, !dbg !94
for.body.165:
  store double %t360, ptr %slot362, !dbg !94
  %t363 = sext i32 %t14 to i64, !dbg !95
  %t364 = load double, ptr %slot362, !dbg !95
  %t365 = getelementptr inbounds ptr, ptr %t1, i64 23, !dbg !95
  %rt.table_number.366 = load ptr, ptr %t365, !invariant.load !8, !dbg !95
  %t367 = call double %rt.table_number.366(ptr %L, i64 %t363, double %t364, ptr @nupp.bytes.8), !dbg !95
  store double %t367, ptr %slot368, !dbg !95
  %t369 = load i1, ptr %slot354, !dbg !96
  br i1 %t369, label %if.then.169, label %if.else.170, !dbg !96
if.then.169:
  %t370 = getelementptr inbounds ptr, ptr %t1, i64 25, !dbg !97
  %rt.string_buffer_append.371 = load ptr, ptr %t370, !invariant.load !8, !dbg !97
  call void %rt.string_buffer_append.371(ptr %L, ptr %slot325, ptr @nupp.bytes.7, i64 1), !dbg !97
  br label %if.end.168, !dbg !97
if.else.170:
  br label %if.end.168, !dbg !97
if.end.168:
  %t372 = load double, ptr %slot368, !dbg !98
  %t373 = fcmp oeq double %t372, 0x0000000000000000, !dbg !98
  br i1 %t373, label %if.then.172, label %if.else.173, !dbg !98
if.then.172:
  %t374 = getelementptr inbounds ptr, ptr %t1, i64 25, !dbg !99
  %rt.string_buffer_append.375 = load ptr, ptr %t374, !invariant.load !8, !dbg !99
  call void %rt.string_buffer_append.375(ptr %L, ptr %slot325, ptr @nupp.bytes.9, i64 2), !dbg !99
  br label %if.end.171, !dbg !99
if.else.173:
  %t376 = load double, ptr %slot368, !dbg !100
  store double %t376, ptr %slot377, !dbg !100
  br label %while.head.174, !dbg !101
while.head.174:
  %t378 = load double, ptr %slot377, !dbg !101
  %t379 = load i32, ptr %slot46, !dbg !101
  %t380 = uitofp i32 %t379 to double, !dbg !101
  %t381 = fcmp olt double %t378, %t380, !dbg !101
  br i1 %t381, label %while.body.175, label %while.end.176, !dbg !101
while.body.175:
  %t382 = load double, ptr %slot377, !dbg !102
  %t383 = fadd double %t382, 0x3FF0000000000000, !dbg !102
  %t384 = getelementptr inbounds ptr, ptr %t1, i64 20, !dbg !102
  %rt.string_byte_lua.385 = load ptr, ptr %t384, !invariant.load !8, !dbg !102
  %t386 = call double %rt.string_byte_lua.385(ptr %L, ptr %t7, i64 %t8, double %t383), !dbg !102
  store double %t386, ptr %slot387, !dbg !102
  %t388 = load double, ptr %slot387, !dbg !103
  %t389 = fcmp oeq double %t388, 0x4047800000000000, !dbg !103
  br i1 %t389, label %or.end.179, label %or.rhs.178, !dbg !103
or.rhs.178:
  %t390 = load i1, ptr %slot11, !dbg !103
  br i1 %t390, label %and.rhs.180, label %and.end.181, !dbg !103
and.rhs.180:
  %t391 = load double, ptr %slot387, !dbg !103
  %t392 = fcmp oeq double %t391, 0x4057000000000000, !dbg !103
  br label %and.end.181, !dbg !103
and.end.181:
  %t393 = phi i1 [ false, %or.rhs.178 ], [ %t392, %and.rhs.180 ], !dbg !103
  br label %or.end.179, !dbg !103
or.end.179:
  %t394 = phi i1 [ true, %while.body.175 ], [ %t393, %and.end.181 ], !dbg !103
  br i1 %t394, label %if.then.182, label %if.else.183, !dbg !103
if.then.182:
  br label %while.end.176, !dbg !104
if.else.183:
  br label %if.end.177, !dbg !104
if.end.177:
  %t395 = load double, ptr %slot377, !dbg !105
  %t396 = fadd double %t395, 0x3FF0000000000000, !dbg !105
  store double %t396, ptr %slot377, !dbg !105
  br label %while.head.174, !dbg !105
while.end.176:
  %t397 = load double, ptr %slot368, !dbg !106
  %t398 = load double, ptr %slot377, !dbg !106
  %t399 = getelementptr inbounds ptr, ptr %t1, i64 26, !dbg !106
  %rt.string_buffer_append_slice.400 = load ptr, ptr %t399, !invariant.load !8, !dbg !106
  call void %rt.string_buffer_append_slice.400(ptr %L, ptr %slot325, ptr %t7, i64 %t8, double %t397, double %t398), !dbg !106
  br label %if.end.171, !dbg !106
if.end.171:
  store i1 true, ptr %slot354, !dbg !107
  br label %for.next.166, !dbg !107
for.next.166:
  %t401 = load double, ptr %slot359, !dbg !107
  %t402 = fadd double %t401, 1.0, !dbg !107
  store double %t402, ptr %slot359, !dbg !107
  br label %for.head.164, !dbg !107
for.end.167:
  %t403 = getelementptr inbounds ptr, ptr %t1, i64 28, !dbg !108
  %rt.string_buffer_finish.404 = load ptr, ptr %t403, !invariant.load !8, !dbg !108
  call void %rt.string_buffer_finish.404(ptr %L, ptr %slot325), !dbg !108
  ret i32 1, !dbg !108
}

define i32 @ks_register_a5aec1231ee04251_5e40cbbf873d89d7__neon(ptr %L) #0 {
entry:
  %slot6 = alloca i64, align 8
  br label %body
body:
  %t1 = call i32 @lua_checkstack(ptr %L, i32 4)
  %t2 = icmp eq i32 %t1, 0
  br i1 %t2, label %lua.raise.1, label %lua.ok.2, !prof !7
lua.raise.1:
  %t3 = call i32 (ptr, ptr, ...) @luaL_error(ptr %L, ptr @nupp.bytes.10, ptr @nupp.bytes.11) nomerge
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
  call void @lua_getfield(ptr %L, i32 -10002, ptr @nupp.bytes.12)
  call void @lua_pushlstring(ptr %L, ptr @nupp.bytes.13, i64 19)
  call void @lua_call(ptr %L, i32 1, i32 1)
  call void @lua_getfield(ptr %L, i32 -1, ptr @nupp.bytes.14)
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
  %t12 = call i32 (ptr, ptr, ...) @luaL_error(ptr %L, ptr @nupp.bytes.10, ptr @nupp.bytes.15) nomerge
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
  %t68 = call i32 (ptr, ptr, ...) @luaL_error(ptr %L, ptr @nupp.bytes.10, ptr @nupp.bytes.15) nomerge
  unreachable
lua.ok.9:
  store ptr %t13, ptr @ks.rt
  call void @lua_settop(ptr %L, i32 -3)
  call void @lua_createtable(ptr %L, i32 0, i32 1)
  call void @lua_pushlstring(ptr %L, ptr @nupp.bytes.16, i64 13)
  call void @lua_pushcclosure(ptr %L, ptr @ks_a5aec1231ee04251_normalize_impl__neon_lua, i32 0)
  call void @lua_rawset(ptr %L, i32 -3)
  ret i32 1
}

attributes #0 = { uwtable "probe-stack"="inline-asm" "frame-pointer"="non-leaf" }
!llvm.dbg.cu = !{!1}
!llvm.module.flags = !{!2, !3}
!0 = !DIFile(filename: "pathtext.nupp", directory: "/private/tmp/nupp-codegen-experiment/src/nupp/io/path")
!1 = distinct !DICompileUnit(language: DW_LANG_C11, file: !0, producer: "nupp", isOptimized: true, runtimeVersion: 0, emissionKind: LineTablesOnly)
!2 = !{i32 7, !"Dwarf Version", i32 4}
!3 = !{i32 2, !"Debug Info Version", i32 3}
!4 = !DISubroutineType(types: !{})
!5 = distinct !DISubprogram(name: "normalizeImpl", scope: !0, file: !0, line: 209, type: !4, scopeLine: 209, spFlags: DISPFlagDefinition | DISPFlagOptimized, unit: !1)
!6 = !DILocation(line: 209, column: 1, scope: !5)
!7 = !{!"branch_weights", i32 1, i32 1048575}
!8 = !{}
!9 = !DILocation(line: 209, column: 5, scope: !5)
!10 = !DILocation(line: 210, column: 5, scope: !5)
!11 = !DILocation(line: 211, column: 5, scope: !5)
!12 = !DILocation(line: 212, column: 5, scope: !5)
!13 = !DILocation(line: 213, column: 5, scope: !5)
!14 = !DILocation(line: 214, column: 9, scope: !5)
!15 = !DILocation(line: 215, column: 9, scope: !5)
!16 = !DILocation(line: 216, column: 9, scope: !5)
!17 = !DILocation(line: 217, column: 9, scope: !5)
!18 = !DILocation(line: 218, column: 13, scope: !5)
!19 = !DILocation(line: 220, column: 13, scope: !5)
!20 = !DILocation(line: 221, column: 13, scope: !5)
!21 = !DILocation(line: 222, column: 13, scope: !5)
!22 = !DILocation(line: 223, column: 17, scope: !5)
!23 = !DILocation(line: 224, column: 17, scope: !5)
!24 = !DILocation(line: 225, column: 17, scope: !5)
!25 = !DILocation(line: 226, column: 21, scope: !5)
!26 = !DILocation(line: 229, column: 13, scope: !5)
!27 = !DILocation(line: 230, column: 13, scope: !5)
!28 = !DILocation(line: 231, column: 17, scope: !5)
!29 = !DILocation(line: 232, column: 21, scope: !5)
!30 = !DILocation(line: 233, column: 21, scope: !5)
!31 = !DILocation(line: 234, column: 25, scope: !5)
!32 = !DILocation(line: 236, column: 21, scope: !5)
!33 = !DILocation(line: 238, column: 17, scope: !5)
!34 = !DILocation(line: 239, column: 17, scope: !5)
!35 = !DILocation(line: 240, column: 21, scope: !5)
!36 = !DILocation(line: 241, column: 25, scope: !5)
!37 = !DILocation(line: 242, column: 25, scope: !5)
!38 = !DILocation(line: 243, column: 29, scope: !5)
!39 = !DILocation(line: 245, column: 25, scope: !5)
!40 = !DILocation(line: 247, column: 21, scope: !5)
!41 = !DILocation(line: 248, column: 25, scope: !5)
!42 = !DILocation(line: 252, column: 13, scope: !5)
!43 = !DILocation(line: 255, column: 5, scope: !5)
!44 = !DILocation(line: 256, column: 5, scope: !5)
!45 = !DILocation(line: 257, column: 5, scope: !5)
!46 = !DILocation(line: 258, column: 9, scope: !5)
!47 = !DILocation(line: 259, column: 9, scope: !5)
!48 = !DILocation(line: 260, column: 13, scope: !5)
!49 = !DILocation(line: 261, column: 13, scope: !5)
!50 = !DILocation(line: 262, column: 17, scope: !5)
!51 = !DILocation(line: 263, column: 17, scope: !5)
!52 = !DILocation(line: 264, column: 21, scope: !5)
!53 = !DILocation(line: 266, column: 17, scope: !5)
!54 = !DILocation(line: 270, column: 5, scope: !5)
!55 = !DILocation(line: 271, column: 9, scope: !5)
!56 = !DILocation(line: 272, column: 9, scope: !5)
!57 = !DILocation(line: 273, column: 13, scope: !5)
!58 = !DILocation(line: 274, column: 13, scope: !5)
!59 = !DILocation(line: 275, column: 17, scope: !5)
!60 = !DILocation(line: 277, column: 13, scope: !5)
!61 = !DILocation(line: 279, column: 9, scope: !5)
!62 = !DILocation(line: 280, column: 9, scope: !5)
!63 = !DILocation(line: 281, column: 13, scope: !5)
!64 = !DILocation(line: 282, column: 13, scope: !5)
!65 = !DILocation(line: 283, column: 13, scope: !5)
!66 = !DILocation(line: 284, column: 17, scope: !5)
!67 = !DILocation(line: 285, column: 21, scope: !5)
!68 = !DILocation(line: 286, column: 21, scope: !5)
!69 = !DILocation(line: 289, column: 13, scope: !5)
!70 = !DILocation(line: 290, column: 17, scope: !5)
!71 = !DILocation(line: 291, column: 17, scope: !5)
!72 = !DILocation(line: 292, column: 17, scope: !5)
!73 = !DILocation(line: 293, column: 21, scope: !5)
!74 = !DILocation(line: 295, column: 17, scope: !5)
!75 = !DILocation(line: 298, column: 9, scope: !5)
!76 = !DILocation(line: 299, column: 13, scope: !5)
!77 = !DILocation(line: 300, column: 13, scope: !5)
!78 = !DILocation(line: 301, column: 17, scope: !5)
!79 = !DILocation(line: 303, column: 13, scope: !5)
!80 = !DILocation(line: 306, column: 5, scope: !5)
!81 = !DILocation(line: 307, column: 9, scope: !5)
!82 = !DILocation(line: 310, column: 5, scope: !5)
!83 = !DILocation(line: 311, column: 5, scope: !5)
!84 = !DILocation(line: 312, column: 5, scope: !5)
!85 = !DILocation(line: 313, column: 9, scope: !5)
!86 = !DILocation(line: 314, column: 9, scope: !5)
!87 = !DILocation(line: 315, column: 13, scope: !5)
!88 = !DILocation(line: 317, column: 13, scope: !5)
!89 = !DILocation(line: 319, column: 9, scope: !5)
!90 = !DILocation(line: 321, column: 5, scope: !5)
!91 = !DILocation(line: 322, column: 9, scope: !5)
!92 = !DILocation(line: 324, column: 5, scope: !5)
!93 = !DILocation(line: 325, column: 20, scope: !5)
!94 = !DILocation(line: 325, column: 5, scope: !5)
!95 = !DILocation(line: 326, column: 9, scope: !5)
!96 = !DILocation(line: 327, column: 9, scope: !5)
!97 = !DILocation(line: 328, column: 13, scope: !5)
!98 = !DILocation(line: 330, column: 9, scope: !5)
!99 = !DILocation(line: 331, column: 13, scope: !5)
!100 = !DILocation(line: 333, column: 13, scope: !5)
!101 = !DILocation(line: 334, column: 13, scope: !5)
!102 = !DILocation(line: 335, column: 17, scope: !5)
!103 = !DILocation(line: 336, column: 17, scope: !5)
!104 = !DILocation(line: 337, column: 21, scope: !5)
!105 = !DILocation(line: 339, column: 17, scope: !5)
!106 = !DILocation(line: 341, column: 13, scope: !5)
!107 = !DILocation(line: 343, column: 9, scope: !5)
!108 = !DILocation(line: 346, column: 5, scope: !5)
