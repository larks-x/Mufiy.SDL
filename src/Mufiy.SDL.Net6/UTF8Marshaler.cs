// Copyright (c) Alexandre Mutel. All rights reserved.
// Licensed under the BSD-Clause 2 license.
// See license.txt file in the project root for full license information.

using System.Runtime.InteropServices;
using System.Text;

namespace SDL;

/// <summary>
/// 提供 UTF-8 字符串与非托管内存之间的转换辅助方法。
/// net6.0 不支持源生成式自定义封送（[CustomMarshaller]/[MarshalUsing]），故此处仅保留辅助转换方法。
/// </summary>
static unsafe class Utf8CustomMarshaller
{
    /// <summary>Converts a string to an unmanaged version.</summary>
    /// <param name="managed">The managed string to convert.</param>
    /// <returns>An unmanaged string.</returns>
    public static byte* ConvertToUnmanaged(string? managed)
    {
        if (managed == null)
            return (byte*)null;

        int lengthPlus1 = UTF8EncodingRelaxed.Default.GetByteCount(managed) + 1;
        byte* pointer = (byte*)NativeMemory.Alloc((nuint)lengthPlus1);
        var span = new Span<byte>(pointer, lengthPlus1);
        int length = UTF8EncodingRelaxed.Default.GetBytes((ReadOnlySpan<char>)managed, span);
        span[length] = 0;
        return pointer;
    }

    /// <summary>Converts an unmanaged string to a managed version.</summary>
    /// <param name="unmanaged">The unmanaged string to convert.</param>
    /// <returns>A managed string.</returns>
    public static string? ConvertToManaged(byte* unmanaged)
    {
        if (unmanaged == null)
            return null;

        return UTF8EncodingRelaxed.Default.GetString(MemoryMarshal.CreateReadOnlySpanFromNullTerminated(unmanaged));
    }

    /// <summary>Converts an unmanaged string to a managed version.</summary>
    /// <param name="unmanaged">The unmanaged string to convert.</param>
    /// <param name="maxLength">The maximum length to convert.</param>
    /// <returns>A managed string.</returns>
    public static string? ConvertToManaged(byte* unmanaged, int maxLength)
    {
        if (unmanaged == null)
            return null;

        ReadOnlySpan<byte> span = new(unmanaged, maxLength);
        int indexOfZero = span.IndexOf((byte)0);
        return indexOfZero < 0 ? UTF8EncodingRelaxed.Default.GetString(span) : UTF8EncodingRelaxed.Default.GetString(span.Slice(0, indexOfZero));
    }

    /// <param name="unmanaged">The memory allocated for the unmanaged string.</param>
    public static void UserFree(byte* unmanaged) => NativeMemory.Free(unmanaged);

    /// <summary>Free the memory for a specified unmanaged string.</summary>
    /// <param name="unmanaged">The memory allocated for the unmanaged string.</param>
    public static void Free(byte* unmanaged)
    {
        // We don't free memory allocated by the marshaller
    }
}

internal sealed class UTF8EncodingRelaxed : UTF8Encoding
{
    public static new readonly UTF8EncodingRelaxed Default = new();

    private UTF8EncodingRelaxed() : base(false, false)
    {
    }
}
