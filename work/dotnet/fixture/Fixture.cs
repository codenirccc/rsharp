using System;
using System.Runtime.InteropServices;

namespace rsharp_dotnet_fixture;

[UnmanagedFunctionPointer(CallingConvention.Cdecl)]
public delegate int AddDelegate(int a, int b);

[UnmanagedFunctionPointer(CallingConvention.Cdecl)]
public delegate int SumDelegate(int n);

[UnmanagedFunctionPointer(CallingConvention.Cdecl)]
public delegate long EchoDelegate(long v);

[UnmanagedFunctionPointer(CallingConvention.Cdecl)]
public delegate double ScaleDelegate(double v, double k);

[UnmanagedFunctionPointer(CallingConvention.Cdecl)]
public delegate int FillDelegate(IntPtr dst, int cap);

[UnmanagedFunctionPointer(CallingConvention.Cdecl)]
public delegate int PackDelegate(int a, int b, int c, int d, int e, int f);

[UnmanagedFunctionPointer(CallingConvention.Cdecl)]
public delegate double BlendDelegate(double a, int b, double c, int d, double e);

public static class Fixture
{
    public static int Add(int a, int b)
    {
        return a + b;
    }

    public static int Mul(int a, int b)
    {
        return a * b;
    }

    public static int SumTo(int n)
    {
        var total = 0;
        for (var i = 1; i <= n; i++)
        {
            total += i;
        }
        return total;
    }

    public static long Echo64(long v)
    {
        return v ^ 0x0F0F0F0F0F0F0F0FL;
    }

    public static double Scale(double v, double k)
    {
        return v * k;
    }

    [UnmanagedCallersOnly]
    public static int Twice(int v)
    {
        return v * 2;
    }

    public static int Pack(int a, int b, int c, int d, int e, int f)
    {
        return a * 100000 + b * 10000 + c * 1000 + d * 100 + e * 10 + f;
    }

    public static double Blend(double a, int b, double c, int d, double e)
    {
        return a + b + c * 2.0 + d * 3.0 + e * 4.0;
    }

    public static unsafe int Fill(IntPtr dst, int cap)
    {
        const string text = "Hello from .NET \u4e16\u754c";
        if (cap < text.Length + 1)
        {
            return -1;
        }
        char* d = (char*)dst;
        for (var i = 0; i < text.Length; i++)
        {
            d[i] = text[i];
        }
        d[text.Length] = '\0';
        return text.Length;
    }
}
