// ... existing code ...
    /// 리퀴드 스테이킹 토큰
    struct LiquidToken {}

    /// 컨트랙트 상태를 저장하는 리소스
    struct StakingPool has key {
        total_staked: u64,
        exchange_rate: u64,
        mint_cap: MintCapability<LiquidToken>,
        burn_cap: BurnCapability<LiquidToken>
    }

    const PRECISION: u64 = 1000000; // 6자리 소수점 정밀도
    const MINIMUM_STAKE: u64 = 1000000; // 최소 스테이킹 금액 (1 INITIA)

    /// 초기화 함수
    public fun initialize(account: &signer) {
        assert!(!exists<StakingPool>(signer::address_of(account)), 1000);
        
        let (mint_cap, burn_cap) = coin::initialize<LiquidToken>(
            account,
            b"Optimized Initia Token",
            b"opINIT",
            6,
            true
        );
// ... existing code ...