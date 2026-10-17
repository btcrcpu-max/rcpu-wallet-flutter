import 'dart:ui' show PlatformDispatcher;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 应用内中英文双语字符串表。
///
/// 设计要点：
/// - 构造参数默认值即中文文案，[AppStrings.en] 逐项覆盖为英文，
///   保证两种语言字段一一对应（漏覆盖时静默回退中文，不会编译失败）；
/// - [AppStrings.current] 为全局当前语言实例，供服务层（支付/钱包等非
///   widget 代码）读取；**默认中文**，未初始化语言 provider 时（如单元
///   测试直接调用服务层）行为与旧版完全一致；
/// - 带参数的文案以方法形式提供，按 [isEn] 分支。
class AppStrings {
  final bool isEn;

  // ---- 应用 ----
  final String appTitle;
  final String appSubtitle;

  // ---- 底部导航 ----
  final String navHome;
  final String navReceive;
  final String navSend;
  final String navSettings;

  // ---- 首页 ----
  final String totalAssets;
  final String pricePending;
  final String nativeAsset;
  final String wrappedAsset;
  final String receive;
  final String send;
  final String settingsNetwork;
  final String noWallet;
  final String noWalletHint;
  final String createImportWallet;
  final String connected;
  final String nodeDisconnected;
  final String nodeConnected;
  final String endpointLabel;
  final String blockHeight;
  final String updatedAt;
  final String reasonLabel;
  final String retry;
  final String close;

  // ---- 设置 ----
  final String addressManagement;
  final String plainAddress;
  final String privateAddress;
  final String bscAddress;
  final String security;
  final String biometric;
  final String exportMnemonic;
  final String network;
  final String rpcNode;
  final String rpcNodeValue;
  final String about;
  final String version;
  final String walletSection;
  final String logoutSwitch;
  final String logoutHint;
  final String bioUnsupported;
  final String bioNotEnrolled;
  final String bioEnableReason;
  final String bioFailed;
  final String exportMnReason;
  final String authFailedNoExport;
  final String noWalletData;
  final String mnemonicCopied;
  final String logoutTitle;
  final String logoutContent;
  final String cancel;
  final String logoutConfirm;
  final String logoutReason;
  final String authFailedLogoutCancelled;
  final String language;
  final String langSystem;
  final String langZh;
  final String langEn;

  // ---- 付款 ----
  final String scanPayTooltip;
  final String scanTooltip;
  final String recipientAddress;
  final String nativeAddrHint;
  final String amount;
  final String confirmSend;
  final String fillAddressAmount;
  final String nativeAddrPrefix;
  final String wrcpuAddrPrefix;
  final String amountInvalid;
  final String amountZero;
  final String wrcpuNotOpen;
  final String walletLocked;
  final String walletNotInit;
  final String paymentSuccess;
  final String ok;

  // ---- 待确认交易 / 最大付款 ----
  final String pendingTxTitle;
  final String txOutLabel;
  final String txInLabel;
  final String maxLabel;
  final String maxFeeHint;

  // ---- 收款 ----
  final String plainSeg;
  final String privateSeg;
  final String privateAddrHint;
  final String plainAddrHint;
  final String addressCopied;
  final String amountOptional;
  final String paymentProtocol;

  // ---- 钱包初始化 ----
  final String createNewWallet;
  final String importExisting;
  final String backupMnemonic;
  final String mnemonicWarning;
  final String backedUpEnter;
  final String mnemonicLabel;
  final String importWallet;
  final String back;
  final String enterMnemonic;
  final String bioProtectTitle;
  final String bioProtectContent;
  final String notNow;
  final String enableNow;
  final String bioEnableVerifyReason;
  final String bioEnableFailedHint;
  final String invalidMnemonic;

  // ---- 扫码 ----
  final String scanTitle;
  final String qrUnrecognized;
  final String cameraStartFailed;
  final String errorCodeLabel;
  final String cameraPermissionHint;
  final String scanHint;

  // ---- 跨链桥 ----
  final String bridgeTitle;
  final String mint;
  final String redeem;
  final String mintWrcpu;
  final String mintStep1;
  final String mintStep2;
  final String copyDepositAddress;
  final String mintProgress;
  final String redeemRcpu;
  final String redeemStep1;
  final String redeemStep2;
  final String redeemStep3;
  final String redeemAmount;
  final String confirmRedeem;

  // ---- 支付/钱包服务层错误 ----
  final String fingerprintFailed;
  final String ctProxyMissing;
  final String nativeSignNotReady;
  final String unsupportedAsset;
  final String amountMustBePositive;
  final String missingCtKey;
  final String missingPrivateAddress;
  final String plainKeyLen;
  final String ctKeyLen;
  final String noSpendableUtxo;
  final String insufficientWithFee;
  final String feeUnderestimated;
  final String ctInputMismatch;
  final String ctOutputMismatch;
  final String ctHexTooShort;
  final String ctPayloadInvalid;
  final String ctPubInvalid;
  final String ctKeyidMismatch;
  final String changeMustBePlain;
  final String onlyPlainRecv;
  final String missingFromAddress;
  final String noSpendableP2wpkh;
  final String plainMustBeV0;
  final String hexOdd;
  final String nativePayAddrPrefix;
  final String wrcpuPayAddrPrefix;
  final String ctBlindingNeeded;

  const AppStrings({
    this.isEn = false,
    this.appTitle = 'RCPU 钱包',
    this.appSubtitle = '原生 RCPU + BSC wRCPU 双链钱包',
    this.navHome = '首页',
    this.navReceive = '收款',
    this.navSend = '付款',
    this.navSettings = '设置',
    this.totalAssets = '总资产',
    this.pricePending = '≈ 联调后获取实时价格',
    this.nativeAsset = '原生资产',
    this.wrappedAsset = 'BSC 包装资产',
    this.receive = '收款',
    this.send = '付款',
    this.settingsNetwork = '设置 / 网络',
    this.noWallet = '尚未创建钱包',
    this.noWalletHint = '创建或导入钱包后即可收发 RCPU / wRCPU',
    this.createImportWallet = '创建 / 导入钱包',
    this.connected = '已连接',
    this.nodeDisconnected = '节点未连接',
    this.nodeConnected = '节点已连接',
    this.endpointLabel = '端点',
    this.blockHeight = '区块高度',
    this.updatedAt = '更新时间',
    this.reasonLabel = '原因',
    this.retry = '重试连接',
    this.close = '关闭',
    this.addressManagement = '地址管理',
    this.plainAddress = '明文地址',
    this.privateAddress = '隐私地址',
    this.bscAddress = 'BSC 地址',
    this.security = '安全',
    this.biometric = '生物识别',
    this.exportMnemonic = '导出助记词',
    this.network = '网络',
    this.rpcNode = 'RPC 节点',
    this.rpcNodeValue = '原生: https://rcpu.ren/rpc | BSC: 公共节点',
    this.about = '关于',
    this.version = '版本',
    this.walletSection = '钱包',
    this.logoutSwitch = '退出 / 切换钱包',
    this.logoutHint = '删除本机钱包数据，返回创建/导入页',
    this.bioUnsupported = '当前设备不支持生物识别',
    this.bioNotEnrolled = '系统未录入指纹/人脸，请先在系统设置中添加',
    this.bioEnableReason = '开启生物识别以解锁钱包',
    this.bioFailed = '生物识别验证失败',
    this.exportMnReason = '验证身份以导出助记词',
    this.authFailedNoExport = '身份验证失败，无法导出助记词',
    this.noWalletData = '未找到钱包数据',
    this.mnemonicCopied = '助记词已复制到剪贴板',
    this.logoutTitle = '退出当前钱包',
    this.logoutContent = '退出将删除本机保存的助记词并清空钱包数据。\n\n'
        '请确认你已备份助记词，否则资产将无法恢复！',
    this.cancel = '取消',
    this.logoutConfirm = '我已备份，退出',
    this.logoutReason = '验证身份以退出钱包',
    this.authFailedLogoutCancelled = '身份验证失败，已取消退出',
    this.language = '语言 / Language',
    this.langSystem = '跟随系统',
    this.langZh = '中文',
    this.langEn = 'English',
    this.scanPayTooltip = '扫码付款',
    this.scanTooltip = '扫码',
    this.recipientAddress = '收款地址',
    this.nativeAddrHint = 'rcpu1... 或 rcpux1...',
    this.amount = '金额',
    this.confirmSend = '确认付款',
    this.fillAddressAmount = '请填写地址和金额',
    this.nativeAddrPrefix = '原生资产收款地址须为 rcpu1 / rcpux1 开头',
    this.wrcpuAddrPrefix = 'wRCPU 收款地址须为 0x 开头',
    this.amountInvalid = '金额格式非法',
    this.amountZero = '金额不能为 0',
    this.wrcpuNotOpen = 'wRCPU 转账功能尚未开放，当前仅支持原生 RCPU',
    this.walletLocked = '钱包未解锁',
    this.walletNotInit = '钱包未初始化',
    this.paymentSuccess = '支付成功',
    this.ok = '确定',
    this.pendingTxTitle = '待确认交易',
    this.txOutLabel = '转出',
    this.txInLabel = '转入',
    this.maxLabel = '最大',
    this.maxFeeHint = '已按最大可转填写，手续费将从付款金额中扣除',
    this.plainSeg = '明文 rcpu1',
    this.privateSeg = '隐私 rcpux1',
    this.privateAddrHint = '隐私地址（推荐收款）',
    this.plainAddrHint = '明文地址（仅限桥存款）',
    this.addressCopied = '地址已复制',
    this.amountOptional = '金额（可选）',
    this.paymentProtocol = '支付协议',
    this.createNewWallet = '创建新钱包',
    this.importExisting = '导入已有钱包',
    this.backupMnemonic = '请备份助记词',
    this.mnemonicWarning = '⚠️ 助记词是恢复钱包的唯一凭证，请妥善保存，不要截图或发送给他人',
    this.backedUpEnter = '我已备份，进入钱包',
    this.mnemonicLabel = '助记词（12 个英文单词，空格分隔）',
    this.importWallet = '导入钱包',
    this.back = '返回',
    this.enterMnemonic = '请输入助记词',
    this.bioProtectTitle = '开启指纹/面容保护',
    this.bioProtectContent = '建议开启生物识别保护钱包：\n'
        '进入付款、导出助记词等敏感操作时将要求验证指纹/面容或锁屏密码。',
    this.notNow = '暂不',
    this.enableNow = '立即开启',
    this.bioEnableVerifyReason = '验证以开启生物识别保护',
    this.bioEnableFailedHint = '验证失败，未开启生物识别（可稍后在设置中开启）',
    this.invalidMnemonic = '助记词无效',
    this.scanTitle = '扫描收款码',
    this.qrUnrecognized = '无法识别的二维码内容，已忽略',
    this.cameraStartFailed = '相机启动失败',
    this.errorCodeLabel = '错误码',
    this.cameraPermissionHint =
        '若错误码为 permissionDenied：设置 → 应用 → rcpu_wallet → 权限 → 相机，选择「允许」后返回重试。',
    this.scanHint = '对准收款方二维码（支持 rcpu: 收款码或地址二维码）',
    this.bridgeTitle = '跨链桥',
    this.mint = '铸造',
    this.redeem = '赎回',
    this.mintWrcpu = '铸造 wRCPU',
    this.mintStep1 = '1. 向桥专属地址存入原生 RCPU（明文地址）',
    this.mintStep2 = '2. 累计满 10 RCPU 后自动铸造 wRCPU 到 BSC 地址',
    this.copyDepositAddress = '复制专属存款地址',
    this.mintProgress = '铸造进度: 0 / 10 RCPU（联调后获取实时进度）',
    this.redeemRcpu = '赎回 RCPU',
    this.redeemStep1 = '1. 在 BSC 上燃烧 wRCPU',
    this.redeemStep2 = '2. 指定收款地址为原生钱包地址',
    this.redeemStep3 = '3. 桥处理完成后 RCPU 直接到账',
    this.redeemAmount = '赎回数量',
    this.confirmRedeem = '确认赎回',
    this.fingerprintFailed = '指纹验证失败',
    this.ctProxyMissing = '隐私地址支付需 CT 代理（当前未配置）',
    this.nativeSignNotReady = '原生签名暂未实现，请稍后重试',
    this.unsupportedAsset = '不支持的资产类型',
    this.amountMustBePositive = '金额必须为正',
    this.missingCtKey = '缺少隐私地址私钥（CT 找零/输入需 m/84\'/1\'/0\'/1/0）',
    this.missingPrivateAddress = '缺少隐私地址（CT 找零接收方）',
    this.plainKeyLen = '明文私钥须为 32 字节 hex',
    this.ctKeyLen = '隐私私钥须为 32 字节 hex',
    this.noSpendableUtxo = '没有可花费的原生 UTXO（余额不足或未同步）',
    this.insufficientWithFee = '余额不足（含手续费）',
    this.feeUnderestimated = '手续费估算不足，请重试',
    this.ctInputMismatch = 'CT 构造返回的输入数不一致',
    this.ctOutputMismatch = '交易输出与付款意图不符，已中止签名以防资金重定向',
    this.ctHexTooShort = 'CT 交易 hex 过短',
    this.ctPayloadInvalid = '隐私地址 payload 非法（应为 0x00||keyid||pub）',
    this.ctPubInvalid = '隐私地址公钥非法（须为压缩点）',
    this.ctKeyidMismatch = '隐私地址 keyid 与公钥不匹配',
    this.changeMustBePlain = '找零地址须为明文 rcpu1（当前不支持 CT 找零）',
    this.onlyPlainRecv = '仅支持原生明文收款地址',
    this.missingFromAddress = '缺少付款地址（fromAddress）',
    this.noSpendableP2wpkh = '没有可花费的 P2WPKH/P2TR UTXO（余额不足或未同步）',
    this.plainMustBeV0 = '明文地址须为 witness v0 P2WPKH（20B program）',
    this.hexOdd = 'hex 长度必须为偶数',
    this.nativePayAddrPrefix = '原生付款地址必须为 rcpu1 / rcpux1',
    this.wrcpuPayAddrPrefix = 'wRCPU 付款地址必须为 0x 开头',
    this.ctBlindingNeeded = '隐私收款需 CT 盲化回填',
  });

  // ---- 带参数文案 ----
  String heightLabel(int h) => isEn ? 'Height $h' : '高度 $h';
  String copiedLabel(String label) => isEn ? '$label copied' : '$label已复制';
  String invalidQr(String e) => isEn ? 'Invalid QR code: $e' : '二维码无效: $e';
  String addressInvalid(String e) =>
      isEn ? 'Invalid address: $e' : '地址格式错误: $e';
  String availableBalance(String bal, String unit) =>
      isEn ? 'Available: $bal $unit' : '可用余额: $bal $unit';
  String paymentFailed(String e) => isEn ? 'Payment failed: $e' : '支付失败: $e';
  String txIdLabel(String txid) =>
      isEn ? 'Transaction ID: $txid' : '交易 ID：$txid';
  String payConfirmReason(String amt) =>
      isEn ? 'Confirm payment of $amt RCPU' : '确认支付 $amt RCPU';
  String insufficient(String avail, String need) => isEn
      ? 'Insufficient balance: $avail RCPU available, $need + fee required'
      : '余额不足：可用 $avail RCPU，需 $need + 手续费';
  String depositAddress(String addr) =>
      isEn ? 'Your deposit address: $addr' : '专属存款地址: $addr';
  String receiveAddress(String addr) =>
      isEn ? 'Receiving address: $addr' : '收款地址: $addr';

  /// 确认数展示（0–5；达到 6 后记录消失，不再展示）。
  String confLabel(int n) => isEn ? 'Confirmations $n/6' : '确认数 $n/6';

  /// 中文实例（默认）。
  static const AppStrings zh = AppStrings();

  /// 英文实例（逐项覆盖）。
  static const AppStrings en = AppStrings(
    isEn: true,
    appTitle: 'RCPU Wallet',
    appSubtitle: 'Native RCPU + BSC wRCPU dual-chain wallet',
    navHome: 'Home',
    navReceive: 'Receive',
    navSend: 'Send',
    navSettings: 'Settings',
    totalAssets: 'Total Assets',
    pricePending: '≈ Live price available after integration',
    nativeAsset: 'Native asset',
    wrappedAsset: 'BSC wrapped asset',
    receive: 'Receive',
    send: 'Send',
    settingsNetwork: 'Settings / Network',
    noWallet: 'No wallet yet',
    noWalletHint: 'Create or import a wallet to send and receive RCPU / wRCPU',
    createImportWallet: 'Create / Import Wallet',
    connected: 'Connected',
    nodeDisconnected: 'Node disconnected',
    nodeConnected: 'Node connected',
    endpointLabel: 'Endpoint',
    blockHeight: 'Block height',
    updatedAt: 'Updated',
    reasonLabel: 'Reason',
    retry: 'Retry',
    close: 'Close',
    addressManagement: 'Addresses',
    plainAddress: 'Plain address',
    privateAddress: 'Private address',
    bscAddress: 'BSC address',
    security: 'Security',
    biometric: 'Biometrics',
    exportMnemonic: 'Export Recovery Phrase',
    network: 'Network',
    rpcNode: 'RPC Node',
    rpcNodeValue: 'Native: https://rcpu.ren/rpc | BSC: public node',
    about: 'About',
    version: 'Version',
    walletSection: 'Wallet',
    logoutSwitch: 'Log Out / Switch Wallet',
    logoutHint: 'Delete local wallet data and return to create/import page',
    bioUnsupported: 'Biometrics not supported on this device',
    bioNotEnrolled:
        'No fingerprint/face enrolled. Please add one in system settings first',
    bioEnableReason: 'Enable biometrics to unlock your wallet',
    bioFailed: 'Biometric authentication failed',
    exportMnReason: 'Verify your identity to export the recovery phrase',
    authFailedNoExport: 'Authentication failed. Recovery phrase not exported',
    noWalletData: 'No wallet data found',
    mnemonicCopied: 'Recovery phrase copied to clipboard',
    logoutTitle: 'Log out of current wallet',
    logoutContent:
        'Logging out deletes the recovery phrase stored on this device and clears wallet data.\n\n'
        'Make sure you have backed up your recovery phrase, otherwise your assets cannot be recovered!',
    cancel: 'Cancel',
    logoutConfirm: 'I have a backup, log out',
    logoutReason: 'Verify your identity to log out',
    authFailedLogoutCancelled: 'Authentication failed. Logout cancelled',
    language: 'Language / 语言',
    langSystem: 'System',
    langZh: '中文',
    langEn: 'English',
    scanPayTooltip: 'Scan to pay',
    scanTooltip: 'Scan',
    recipientAddress: 'Recipient address',
    nativeAddrHint: 'rcpu1... or rcpux1...',
    amount: 'Amount',
    confirmSend: 'Confirm',
    fillAddressAmount: 'Please enter address and amount',
    nativeAddrPrefix: 'Native asset address must start with rcpu1 / rcpux1',
    wrcpuAddrPrefix: 'wRCPU address must start with 0x',
    amountInvalid: 'Invalid amount format',
    amountZero: 'Amount cannot be 0',
    wrcpuNotOpen:
        'wRCPU transfers are not available yet; only native RCPU is supported',
    walletLocked: 'Wallet locked',
    walletNotInit: 'Wallet not initialized',
    paymentSuccess: 'Payment Successful',
    ok: 'OK',
    pendingTxTitle: 'Pending Transactions',
    txOutLabel: 'Sent',
    txInLabel: 'Received',
    maxLabel: 'MAX',
    maxFeeHint: 'Max amount filled; the network fee will be deducted from it',
    plainSeg: 'Plain rcpu1',
    privateSeg: 'Private rcpux1',
    privateAddrHint: 'Private address (recommended)',
    plainAddrHint: 'Plain address (bridge deposits only)',
    addressCopied: 'Address copied',
    amountOptional: 'Amount (optional)',
    paymentProtocol: 'Payment URI',
    createNewWallet: 'Create New Wallet',
    importExisting: 'Import Existing Wallet',
    backupMnemonic: 'Back Up Your Recovery Phrase',
    mnemonicWarning:
        '⚠️ The recovery phrase is the only credential to restore your wallet. Keep it safe — do not screenshot or share it with anyone',
    backedUpEnter: 'I have backed it up, enter wallet',
    mnemonicLabel: 'Recovery phrase (12 English words, space separated)',
    importWallet: 'Import Wallet',
    back: 'Back',
    enterMnemonic: 'Please enter your recovery phrase',
    bioProtectTitle: 'Enable Fingerprint/Face Protection',
    bioProtectContent:
        'It is recommended to protect your wallet with biometrics:\n'
        'Sensitive actions such as payments and exporting the recovery phrase will require fingerprint/face or lock-screen verification.',
    notNow: 'Not now',
    enableNow: 'Enable',
    bioEnableVerifyReason: 'Verify to enable biometric protection',
    bioEnableFailedHint:
        'Verification failed. Biometrics not enabled (you can enable it later in Settings)',
    invalidMnemonic: 'Invalid recovery phrase',
    scanTitle: 'Scan Payment Code',
    qrUnrecognized: 'Unrecognized QR content, ignored',
    cameraStartFailed: 'Camera failed to start',
    errorCodeLabel: 'Error code',
    cameraPermissionHint:
        'If the error code is permissionDenied: go to Settings → Apps → rcpu_wallet → Permissions → Camera, choose "Allow", then return and retry.',
    scanHint:
        'Point at the payee QR code (rcpu: payment code or address QR supported)',
    bridgeTitle: 'Bridge',
    mint: 'Mint',
    redeem: 'Redeem',
    mintWrcpu: 'Mint wRCPU',
    mintStep1: '1. Deposit native RCPU to your bridge address (plain address)',
    mintStep2:
        '2. Once 10 RCPU accumulates, wRCPU is minted to your BSC address automatically',
    copyDepositAddress: 'Copy Deposit Address',
    mintProgress: 'Mint progress: 0 / 10 RCPU (live progress after integration)',
    redeemRcpu: 'Redeem RCPU',
    redeemStep1: '1. Burn wRCPU on BSC',
    redeemStep2: '2. Set the receiving address to your native wallet address',
    redeemStep3: '3. RCPU arrives directly after the bridge processes it',
    redeemAmount: 'Redeem amount',
    confirmRedeem: 'Confirm Redeem',
    fingerprintFailed: 'Fingerprint verification failed',
    ctProxyMissing:
        'Private address payment requires the CT coprocessor (not configured)',
    nativeSignNotReady: 'Native signing not implemented yet, please try again later',
    unsupportedAsset: 'Unsupported asset type',
    amountMustBePositive: 'Amount must be positive',
    missingCtKey:
        'Missing private-address key (CT change/inputs need m/84\'/1\'/0\'/1/0)',
    missingPrivateAddress: 'Missing private address (CT change recipient)',
    plainKeyLen: 'Plain key must be 32-byte hex',
    ctKeyLen: 'Private key must be 32-byte hex',
    noSpendableUtxo: 'No spendable native UTXOs (insufficient balance or not synced)',
    insufficientWithFee: 'Insufficient balance (including fee)',
    feeUnderestimated: 'Fee underestimated, please retry',
    ctInputMismatch: 'CT build returned mismatched input count',
    ctOutputMismatch:
        'Transaction outputs do not match the payment intent; signing aborted',
    ctHexTooShort: 'CT transaction hex too short',
    ctPayloadInvalid: 'Invalid private address payload (expected 0x00||keyid||pub)',
    ctPubInvalid: 'Invalid private address public key (must be compressed)',
    ctKeyidMismatch: 'Private address keyid does not match public key',
    changeMustBePlain: 'Change address must be plain rcpu1 (CT change not supported)',
    onlyPlainRecv: 'Only native plain receiving addresses are supported',
    missingFromAddress: 'Missing sender address (fromAddress)',
    noSpendableP2wpkh:
        'No spendable P2WPKH/P2TR UTXOs (insufficient balance or not synced)',
    plainMustBeV0: 'Plain address must be witness v0 P2WPKH (20-byte program)',
    hexOdd: 'Hex length must be even',
    nativePayAddrPrefix: 'Native payment address must be rcpu1 / rcpux1',
    wrcpuPayAddrPrefix: 'wRCPU payment address must start with 0x',
    ctBlindingNeeded: 'Private receiving requires CT blinding',
  );

  /// 全局当前语言实例（服务层使用）。
  ///
  /// 默认中文；语言 provider 解析/切换后同步更新。单元测试不经过
  /// provider，因此测试中始终为中文，与既有断言兼容。
  static AppStrings current = zh;
}

/// 语言选择：跟随系统 / 中文 / English。
enum AppLanguage { system, zh, en }

/// 按选择解析出实际字符串表。
AppStrings resolveAppStrings(AppLanguage sel) {
  switch (sel) {
    case AppLanguage.zh:
      return AppStrings.zh;
    case AppLanguage.en:
      return AppStrings.en;
    case AppLanguage.system:
      final code = PlatformDispatcher.instance.locale.languageCode;
      return code == 'zh' ? AppStrings.zh : AppStrings.en;
  }
}

/// 语言选择 notifier：启动时读取持久化选择，切换后立即生效并写盘。
class LanguageSelectionNotifier extends StateNotifier<AppLanguage> {
  static const String _kKey = 'app_language';

  LanguageSelectionNotifier() : super(AppLanguage.system) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getString(_kKey);
    final sel = AppLanguage.values.asNameMap()[v] ?? AppLanguage.system;
    state = sel;
    AppStrings.current = resolveAppStrings(sel);
  }

  Future<void> setLanguage(AppLanguage sel) async {
    state = sel;
    AppStrings.current = resolveAppStrings(sel);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kKey, sel.name);
  }
}

/// 用户语言选择 provider。
final languageSelectionProvider =
    StateNotifierProvider<LanguageSelectionNotifier, AppLanguage>(
        (ref) => LanguageSelectionNotifier());

/// 当前生效字符串表 provider（UI 统一 watch 此项）。
final appStringsProvider = Provider<AppStrings>((ref) {
  final sel = ref.watch(languageSelectionProvider);
  final s = resolveAppStrings(sel);
  // 同步全局实例，保证服务层（支付/钱包）与 UI 语言一致。
  AppStrings.current = s;
  return s;
});

