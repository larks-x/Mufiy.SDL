// Copyright (c) Amer Koleci and Contributors.
// Licensed under the MIT License (MIT). See LICENSE in the repository root for more information.

// net6.0 的 BCL 未提供 [UnscopedRef]（.NET 7 引入），此处补充等价声明，
// 以便 Roslyn 在 net6.0 目标下仍保留结构体 ref 成员的原有逃逸语义。

namespace System.Diagnostics.CodeAnalysis;

/// <summary>表示方法返回的 ref 或 ref/out 参数的作用域不受接收者（this）限制，可以安全逃逸。</summary>
[AttributeUsage(AttributeTargets.Method | AttributeTargets.Property | AttributeTargets.Parameter, AllowMultiple = false, Inherited = false)]
internal sealed class UnscopedRefAttribute : Attribute
{
}
