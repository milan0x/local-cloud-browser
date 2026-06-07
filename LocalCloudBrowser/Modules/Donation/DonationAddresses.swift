import Foundation

struct DonationEntry: Identifiable {
    let id: String
    let label: String
    let address: String
}

enum DonationAddress {
    static let btc = "bc1qx5su0mgr2vtthfwgcvkdsz7mqq7xx936fmv0np"
    static let usdtTrc20 = "TFRD6nhY4zFk1KyHQUwiiZMpTYPwyjxZ9N"
    static let evm = "0xD6832B71528Dc5Ac2E4e7F33CC1c75A0448A1E9B"
    static let btcBackup = "bc1ql2y2v6k5kr40mg2g0l5u3s5lg390nv5s0adqcu"

    static let all: [DonationEntry] = [
        DonationEntry(id: "btc", label: "BTC", address: btc),
        DonationEntry(id: "usdt-trc20", label: "USDT (TRC20)", address: usdtTrc20),
        DonationEntry(id: "eth-erc20", label: "ETH / ERC20", address: evm),
        DonationEntry(id: "bnb-bep20", label: "BNB / BEP20", address: evm)
    ]
}
