param(
    [string]$TargetPath,
    [string]$PfxPath,
    [string]$Password = "cc_nohotkey",
    [switch]$CreateCert,
    [string]$PublisherCN = "CN=54418920-1845-464B-A595-EDBEA032F08F",
    [string]$OutDir = "."
)
$ErrorActionPreference = "Stop"

if ($CreateCert) {
    New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
    $rsa = [System.Security.Cryptography.RSA]::Create(2048)
    $req = New-Object System.Security.Cryptography.X509Certificates.CertificateRequest(
        $PublisherCN,
        $rsa,
        [System.Security.Cryptography.HashAlgorithmName]::SHA256,
        [System.Security.Cryptography.RSASignaturePadding]::Pkcs1
    )
    $req.CertificateExtensions.Add((New-Object System.Security.Cryptography.X509Certificates.X509BasicConstraintsExtension($false, $false, 0, $true)))
    $req.CertificateExtensions.Add((New-Object System.Security.Cryptography.X509Certificates.X509KeyUsageExtension([System.Security.Cryptography.X509Certificates.X509KeyUsageFlags]::DigitalSignature, $true)))
    $oids = New-Object System.Security.Cryptography.OidCollection
    [void]$oids.Add((New-Object System.Security.Cryptography.Oid("1.3.6.1.5.5.7.3.3")))
    $req.CertificateExtensions.Add((New-Object System.Security.Cryptography.X509Certificates.X509EnhancedKeyUsageExtension($oids, $true)))

    $cert = $req.CreateSelfSigned([DateTimeOffset]::Parse("2024-01-01T00:00:00Z"), [DateTimeOffset]::Parse("2045-01-01T00:00:00Z"))
    $pfxOut = Join-Path $OutDir "cc_nohotkey.pfx"
    $cerOut = Join-Path $OutDir "cc_nohotkey.cer"
    [System.IO.File]::WriteAllBytes($pfxOut, $cert.Export([System.Security.Cryptography.X509Certificates.X509ContentType]::Pfx, $Password))
    [System.IO.File]::WriteAllBytes($cerOut, $cert.Export([System.Security.Cryptography.X509Certificates.X509ContentType]::Cert))
    Write-Output "Created PFX: $pfxOut"
    Write-Output "Created CER: $cerOut"
    Write-Output "Subject: $($cert.Subject) | Thumbprint: $($cert.Thumbprint)"
    if (-not $TargetPath) { exit 0 }
    if (-not $PfxPath) { $PfxPath = $pfxOut }
}

if (-not $TargetPath -or -not $PfxPath) {
    throw "Usage: sign_appx.ps1 -CreateCert [-PublisherCN 'CN=...'] [-OutDir <dir>] | -TargetPath <file.appx|.appxbundle> -PfxPath <file.pfx> -Password <pwd>"
}

$cs = @'
using System;
using System.Runtime.InteropServices;

public static class AppxSipSigner {
    [StructLayout(LayoutKind.Sequential)]
    public struct CRYPT_DATA_BLOB {
        public uint cbData;
        public IntPtr pbData;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct SIGNER_FILE_INFO {
        public uint cbSize;
        [MarshalAs(UnmanagedType.LPWStr)] public string pwszFileName;
        public IntPtr hFile;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct SIGNER_SUBJECT_INFO {
        public uint cbSize;
        public IntPtr pdwIndex;
        public uint dwSubjectChoice;
        public IntPtr pSignerFileInfo;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct SIGNER_CERT_STORE_INFO {
        public uint cbSize;
        public IntPtr pSigningCert;
        public uint dwCertPolicy;
        public IntPtr hCertStore;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct SIGNER_CERT {
        public uint cbSize;
        public uint dwCertChoice;
        public IntPtr pCertStoreInfo;
        public IntPtr hwnd;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct SIGNER_SIGNATURE_INFO {
        public uint cbSize;
        public uint algidHash;
        public uint dwAttrChoice;
        public IntPtr pAttrAuthcode;
        public IntPtr psAuthenticated;
        public IntPtr psUnauthenticated;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct SIGNER_SIGN_EX2_PARAMS {
        public uint dwFlags;
        public IntPtr pSubjectInfo;
        public IntPtr pSignerCert;
        public IntPtr pSignatureInfo;
        public IntPtr pProviderInfo;
        public uint dwTimestampFlags;
        public IntPtr pszTimestampAlgorithmOid;
        public IntPtr pwszHttpTimeStamp;
        public IntPtr psRequest;
        public IntPtr pSipData;
        public IntPtr ppSignerContext;
        public IntPtr pCryptoPolicy;
        public IntPtr pSignInfo;
        public IntPtr pReserved;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct APPX_SIP_CLIENT_DATA {
        public IntPtr pSignerParams;
        public IntPtr pAppxSipState;
    }

    [DllImport("crypt32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    static extern IntPtr PFXImportCertStore(ref CRYPT_DATA_BLOB pPFX, string szPassword, uint dwFlags);

    [DllImport("crypt32.dll", SetLastError = true)]
    static extern IntPtr CertEnumCertificatesInStore(IntPtr hCertStore, IntPtr pPrevCertContext);

    [DllImport("crypt32.dll", SetLastError = true)]
    static extern bool CertFreeCertificateContext(IntPtr pCertContext);

    [DllImport("crypt32.dll", SetLastError = true)]
    static extern bool CertCloseStore(IntPtr hCertStore, uint dwFlags);

    [DllImport("mssign32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    static extern int SignerSignEx2(
        uint dwFlags,
        IntPtr pSubjectInfo,
        IntPtr pSignerCert,
        IntPtr pSignatureInfo,
        IntPtr pProviderInfo,
        uint dwTimestampFlags,
        IntPtr pszTimestampAlgorithmOid,
        IntPtr pwszHttpTimeStamp,
        IntPtr psRequest,
        IntPtr pSipData,
        out IntPtr ppSignerContext,
        IntPtr pCryptoPolicy,
        IntPtr pSignInfo,
        IntPtr pReserved
    );

    [DllImport("mssign32.dll", SetLastError = true)]
    static extern int SignerFreeSignerContext(IntPtr pSignerContext);

    public static void SignFile(string filePath, byte[] pfxBytes, string password) {
        IntPtr pPfx = Marshal.AllocHGlobal(pfxBytes.Length);
        Marshal.Copy(pfxBytes, 0, pPfx, pfxBytes.Length);
        var blob = new CRYPT_DATA_BLOB { cbData = (uint)pfxBytes.Length, pbData = pPfx };
        IntPtr hStore = PFXImportCertStore(ref blob, password, 0x00008000);
        Marshal.FreeHGlobal(pPfx);
        if (hStore == IntPtr.Zero) throw new Exception("PFXImportCertStore failed: " + Marshal.GetLastWin32Error());

        IntPtr pCert = CertEnumCertificatesInStore(hStore, IntPtr.Zero);
        if (pCert == IntPtr.Zero) { CertCloseStore(hStore, 0); throw new Exception("No cert in store"); }

        IntPtr pdwIndex = Marshal.AllocHGlobal(4);
        Marshal.WriteInt32(pdwIndex, 0);
        var fi = new SIGNER_FILE_INFO { cbSize = (uint)Marshal.SizeOf(typeof(SIGNER_FILE_INFO)), pwszFileName = filePath, hFile = IntPtr.Zero };
        IntPtr pFi = Marshal.AllocHGlobal(Marshal.SizeOf(fi));
        Marshal.StructureToPtr(fi, pFi, false);

        var si = new SIGNER_SUBJECT_INFO { cbSize = (uint)Marshal.SizeOf(typeof(SIGNER_SUBJECT_INFO)), pdwIndex = pdwIndex, dwSubjectChoice = 1, pSignerFileInfo = pFi };
        IntPtr pSi = Marshal.AllocHGlobal(Marshal.SizeOf(si));
        Marshal.StructureToPtr(si, pSi, false);

        var csi = new SIGNER_CERT_STORE_INFO { cbSize = (uint)Marshal.SizeOf(typeof(SIGNER_CERT_STORE_INFO)), pSigningCert = pCert, dwCertPolicy = 2, hCertStore = hStore };
        IntPtr pCsi = Marshal.AllocHGlobal(Marshal.SizeOf(csi));
        Marshal.StructureToPtr(csi, pCsi, false);

        var sc = new SIGNER_CERT { cbSize = (uint)Marshal.SizeOf(typeof(SIGNER_CERT)), dwCertChoice = 2, pCertStoreInfo = pCsi, hwnd = IntPtr.Zero };
        IntPtr pSc = Marshal.AllocHGlobal(Marshal.SizeOf(sc));
        Marshal.StructureToPtr(sc, pSc, false);

        var sig = new SIGNER_SIGNATURE_INFO { cbSize = (uint)Marshal.SizeOf(typeof(SIGNER_SIGNATURE_INFO)), algidHash = 0x800C, dwAttrChoice = 0 };
        IntPtr pSig = Marshal.AllocHGlobal(Marshal.SizeOf(sig));
        Marshal.StructureToPtr(sig, pSig, false);

        IntPtr pParams = Marshal.AllocHGlobal(Marshal.SizeOf(typeof(SIGNER_SIGN_EX2_PARAMS)));
        IntPtr pSipData = Marshal.AllocHGlobal(Marshal.SizeOf(typeof(APPX_SIP_CLIENT_DATA)));
        IntPtr pCtxOut = Marshal.AllocHGlobal(IntPtr.Size);
        Marshal.WriteIntPtr(pCtxOut, IntPtr.Zero);

        var prm = new SIGNER_SIGN_EX2_PARAMS {
            dwFlags = 0, pSubjectInfo = pSi, pSignerCert = pSc, pSignatureInfo = pSig, pSipData = pSipData, ppSignerContext = pCtxOut
        };
        Marshal.StructureToPtr(prm, pParams, false);

        var sip = new APPX_SIP_CLIENT_DATA { pSignerParams = pParams, pAppxSipState = IntPtr.Zero };
        Marshal.StructureToPtr(sip, pSipData, false);

        IntPtr signerCtx = IntPtr.Zero;
        try {
            int hr = SignerSignEx2(0, pSi, pSc, pSig, IntPtr.Zero, 0, IntPtr.Zero, IntPtr.Zero, IntPtr.Zero, pSipData, out signerCtx, IntPtr.Zero, IntPtr.Zero, IntPtr.Zero);
            var sipAfter = (APPX_SIP_CLIENT_DATA)Marshal.PtrToStructure(pSipData, typeof(APPX_SIP_CLIENT_DATA));
            if (sipAfter.pAppxSipState != IntPtr.Zero) Marshal.Release(sipAfter.pAppxSipState);
            if (signerCtx != IntPtr.Zero) SignerFreeSignerContext(signerCtx);
            if (hr != 0) throw new Exception("SignerSignEx2 failed HR=0x" + hr.ToString("X8"));
        } finally {
            Marshal.FreeHGlobal(pCtxOut);
            Marshal.FreeHGlobal(pSipData);
            Marshal.FreeHGlobal(pParams);
            Marshal.DestroyStructure(pSig, typeof(SIGNER_SIGNATURE_INFO)); Marshal.FreeHGlobal(pSig);
            Marshal.DestroyStructure(pSc, typeof(SIGNER_CERT)); Marshal.FreeHGlobal(pSc);
            Marshal.DestroyStructure(pCsi, typeof(SIGNER_CERT_STORE_INFO)); Marshal.FreeHGlobal(pCsi);
            Marshal.DestroyStructure(pSi, typeof(SIGNER_SUBJECT_INFO)); Marshal.FreeHGlobal(pSi);
            Marshal.DestroyStructure(pFi, typeof(SIGNER_FILE_INFO)); Marshal.FreeHGlobal(pFi);
            Marshal.FreeHGlobal(pdwIndex);
            CertFreeCertificateContext(pCert);
            CertCloseStore(hStore, 0);
        }
    }
}
'@
Add-Type -TypeDefinition $cs -Language CSharp
$pfxBytes = [System.IO.File]::ReadAllBytes($PfxPath)
[AppxSipSigner]::SignFile($TargetPath, $pfxBytes, $Password)
Get-AuthenticodeSignature $TargetPath | Format-List Path, Status, StatusMessage
