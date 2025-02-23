module optia::liquid_staking {
    use std::signer;
    use std::error;
    use std::string::{Self, String};
    use initia_std::coin;
    use initia_std::event;
    use initia_std::fungible_asset;
    use initia_std::object;
    use initia_std::staking;
    use optia::coins;

    /// Contract admin address
    const ADMIN_ADDRESS: address = @admin;

    // ==================== Error Codes ====================

    /// Error if amount is invalid
    const EINVALID_AMOUNT: u64 = 1;
    /// Error if balance is insufficient
    const EINSUFFICIENT_BALANCE: u64 = 2;
    /// Error if contract is not initialized
    const ECONTRACT_NOT_INITIALIZED: u64 = 3;
    /// Error if caller is not admin
    const EINVALID_ADMIN: u64 = 4;
    /// Error if contract is already initialized
    const ECONTRACT_ALREADY_INITIALIZED: u64 = 5;
    /// Error if arithmetic operation overflows
    const EARITHMETIC_ERROR: u64 = 6;
    /// Error if reward amount is invalid
    const EINVALID_REWARD_AMOUNT: u64 = 7;
    /// Error if reward amount is zero
    const EZERO_REWARD: u64 = 7;
    /// Error if distribution failed
    const EDISTRIBUTION_FAILED: u64 = 8;

    // ==================== Constants ====================

    /// Scaling factor for exchange rate calculations (1:1 = 1000000)
    const EXCHANGE_RATE_SCALE: u64 = 1000000;
    
    /// Minimum amount that can be staked (1 INIT)
    const MINIMUM_STAKE: u64 = 1000000;

    /// Maximum amount that can be staked (prevent overflow)
    const MAXIMUM_STAKE: u64 = 18446744073709551615; // u64::MAX

    /// Unstaking period in days (20 days for VIP Gauge voting power)
    const UNSTAKING_PERIOD: u64 = 20;

    /// Default reward claim interval (24 hours in seconds)
    const DEFAULT_REWARD_CLAIM_INTERVAL: u64 = 86400;

    /// Minimum reward claim interval (1 hour in seconds)
    const MIN_REWARD_CLAIM_INTERVAL: u64 = 3600;

    /// Reward distribution ratios (scaled by RATIO_SCALE)
    const RATIO_SCALE: u64 = 100;
    const MEV_BIDDING_RATIO: u64 = 10;  // 10%
    const PROTOCOL_FEE_RATIO: u64 = 10;  // 10%
    const LP_REWARD_RATIO: u64 = 80;     // 80%

    // ==================== Resources ====================

    struct LiquidStaking has key {
        /// Total amount of INIT tokens staked
        total_staked: u64,
        /// Exchange rate between INIT and opINIT
        exchange_rate: u64,
        /// Validator address
        validator: String,
        /// Validator operator address in bytes
        validator_operator: vector<u8>,
        /// Unstaking period in days
        unstaking_period: u64,
        /// Total delegation amount
        total_delegation: u64,
        /// Last reward claim timestamp
        last_reward_claim: u64,
        /// Reward claim interval in seconds
        reward_claim_interval: u64
    }

    #[event]
    struct StakeEvent has drop, store {
        staker: address,
        amount: u64,
        validator: String
    }

    #[event]
    struct UnstakeEvent has drop, store {
        staker: address,
        amount: u64,
        validator: String
    }

    #[event]
    struct ValidatorUpdateEvent has drop, store {
        old_validator: String,
        new_validator: String,
        admin: address
    }

    #[event]
    struct RewardClaimedEvent has drop, store {
        admin: address,
        amount: u64,
        validator: String,
        timestamp: u64
    }

    #[event]
    struct RewardDistributedEvent has drop, store {
        total_amount: u64,
        mev_amount: u64,
        protocol_amount: u64,
        lp_amount: u64,
        timestamp: u64
    }

    // ==================== Public Functions ====================

    /// Check if contract is initialized
    public fun is_initialized(): bool {
        exists<LiquidStaking>(ADMIN_ADDRESS)
    }

    /// Initialize the liquid staking contract
    public fun initialize(admin: &signer, validator: String, validator_operator: vector<u8>) {
        let admin_addr = signer::address_of(admin);
        assert!(admin_addr == ADMIN_ADDRESS, error::permission_denied(EINVALID_ADMIN));
        assert!(!is_initialized(), error::already_exists(ECONTRACT_ALREADY_INITIALIZED));

        // Register for staking
        if (!staking::is_account_registered(admin_addr)) {
            staking::register(admin);
        };

        move_to(admin, LiquidStaking {
            total_staked: 0,
            exchange_rate: EXCHANGE_RATE_SCALE,
            validator,
            validator_operator,
            unstaking_period: UNSTAKING_PERIOD,
            total_delegation: 0,
            last_reward_claim: 0,
            reward_claim_interval: DEFAULT_REWARD_CLAIM_INTERVAL
        });
    }

    /// Update validator address (only admin)
    public fun update_validator(admin: &signer, new_validator: String, new_validator_operator: vector<u8>) acquires LiquidStaking {
        let admin_addr = signer::address_of(admin);
        assert!(admin_addr == ADMIN_ADDRESS, error::permission_denied(EINVALID_ADMIN));
        assert!(is_initialized(), error::not_found(ECONTRACT_NOT_INITIALIZED));

        let liquid_staking = borrow_global_mut<LiquidStaking>(ADMIN_ADDRESS);
        let old_validator = liquid_staking.validator;
        
        liquid_staking.validator = new_validator;
        liquid_staking.validator_operator = new_validator_operator;

        event::emit(ValidatorUpdateEvent {
            old_validator,
            new_validator,
            admin: admin_addr
        });
    }

    /// Stake INIT tokens and receive opINIT tokens
    public fun stake(staker: &signer, amount: u64) acquires LiquidStaking {
        assert!(is_initialized(), error::not_found(ECONTRACT_NOT_INITIALIZED));
        assert!(amount >= MINIMUM_STAKE, error::invalid_argument(EINVALID_AMOUNT));
        assert!(amount <= MAXIMUM_STAKE, error::invalid_argument(EINVALID_AMOUNT));
        
        let staker_addr = signer::address_of(staker);
        let staker_account = object::address_to_object<fungible_asset::Metadata>(staker_addr);
        let liquid_staking = borrow_global_mut<LiquidStaking>(ADMIN_ADDRESS);
        
        // Check for arithmetic overflow
        assert!(MAXIMUM_STAKE - liquid_staking.total_staked >= amount, error::invalid_argument(EARITHMETIC_ERROR));
        
        // Get INIT tokens from staker and delegate to validator
        let metadata = coin::metadata(@initia_std, string::utf8(b"INIT"));
        staking::delegate_script(
            staker,
            metadata,
            liquid_staking.validator,
            amount
        );
        
        // Mint and send opINIT tokens to staker
        let minted_coins = coins::mint_staked_init(amount);
        fungible_asset::deposit(staker_account, minted_coins);
        
        // Update state
        liquid_staking.total_staked = liquid_staking.total_staked + amount;
        liquid_staking.total_delegation = liquid_staking.total_delegation + amount;
        
        event::emit(StakeEvent {
            staker: staker_addr,
            amount,
            validator: liquid_staking.validator
        });
    }

    /// Unstake opINIT tokens and receive INIT tokens
    public fun unstake(staker: &signer, amount: u64) acquires LiquidStaking {
        assert!(is_initialized(), error::not_found(ECONTRACT_NOT_INITIALIZED));
        assert!(amount > 0, error::invalid_argument(EINVALID_AMOUNT));
        
        let staker_addr = signer::address_of(staker);
        let liquid_staking = borrow_global_mut<LiquidStaking>(ADMIN_ADDRESS);
        
        let unstake_amount = (amount * EXCHANGE_RATE_SCALE) / liquid_staking.exchange_rate;
        assert!(unstake_amount > 0, error::invalid_argument(EINVALID_AMOUNT));
        assert!(unstake_amount <= liquid_staking.total_staked, error::invalid_argument(EINSUFFICIENT_BALANCE));
        
        // Burn opINIT tokens
        let staked_coins = coin::withdraw(staker, coins::get_staked_init_metadata(), amount);
        coins::burn_staked_init(staked_coins);
        
        // Undelegate from validator
        let metadata = coin::metadata(@initia_std, string::utf8(b"INIT"));
        staking::undelegate_script(
            staker,
            metadata,
            liquid_staking.validator,
            unstake_amount
        );
        
        // Update state
        liquid_staking.total_staked = liquid_staking.total_staked - unstake_amount;
        liquid_staking.total_delegation = liquid_staking.total_delegation - unstake_amount;
        
        event::emit(UnstakeEvent {
            staker: staker_addr,
            amount: unstake_amount,
            validator: liquid_staking.validator
        });
    }

    /// Get current exchange rate between INIT and opINIT
    public fun get_exchange_rate(): u64 acquires LiquidStaking {
        assert!(is_initialized(), error::not_found(ECONTRACT_NOT_INITIALIZED));
        borrow_global<LiquidStaking>(ADMIN_ADDRESS).exchange_rate
    }

    /// Get total amount of INIT tokens staked
    public fun get_total_staked(): u64 acquires LiquidStaking {
        assert!(is_initialized(), error::not_found(ECONTRACT_NOT_INITIALIZED));
        borrow_global<LiquidStaking>(ADMIN_ADDRESS).total_staked
    }

    /// Get total amount of INIT tokens delegated
    public fun get_total_delegation(): u64 acquires LiquidStaking {
        assert!(is_initialized(), error::not_found(ECONTRACT_NOT_INITIALIZED));
        borrow_global<LiquidStaking>(ADMIN_ADDRESS).total_delegation
    }

    /// Get validator address
    public fun get_validator(): String acquires LiquidStaking {
        assert!(is_initialized(), error::not_found(ECONTRACT_NOT_INITIALIZED));
        borrow_global<LiquidStaking>(ADMIN_ADDRESS).validator
    }

    /// Get validator operator address
    public fun get_validator_operator(): vector<u8> acquires LiquidStaking {
        assert!(is_initialized(), error::not_found(ECONTRACT_NOT_INITIALIZED));
        borrow_global<LiquidStaking>(ADMIN_ADDRESS).validator_operator
    }

    /// Get unstaking period
    public fun get_unstaking_period(): u64 acquires LiquidStaking {
        assert!(is_initialized(), error::not_found(ECONTRACT_NOT_INITIALIZED));
        borrow_global<LiquidStaking>(ADMIN_ADDRESS).unstaking_period
    }

    /// Update reward claim interval (only admin)
    public entry fun update_reward_claim_interval(admin: &signer, new_interval: u64) acquires LiquidStaking {
        let admin_addr = signer::address_of(admin);
        assert!(admin_addr == ADMIN_ADDRESS, error::permission_denied(EINVALID_ADMIN));
        assert!(is_initialized(), error::not_found(ECONTRACT_NOT_INITIALIZED));
        assert!(new_interval >= MIN_REWARD_CLAIM_INTERVAL, error::invalid_argument(EINVALID_AMOUNT));

        let liquid_staking = borrow_global_mut<LiquidStaking>(ADMIN_ADDRESS);
        liquid_staking.reward_claim_interval = new_interval;
    }

    /// Check if rewards can be claimed
    public fun can_claim_rewards(): bool acquires LiquidStaking {
        assert!(is_initialized(), error::not_found(ECONTRACT_NOT_INITIALIZED));
        
        let liquid_staking = borrow_global<LiquidStaking>(ADMIN_ADDRESS);
        let (_, current_time) = block::get_block_info();
        
        current_time >= liquid_staking.last_reward_claim + liquid_staking.reward_claim_interval
    }

    /// Try to claim rewards and distribute them according to policy
    public entry fun try_claim_rewards(admin: &signer) acquires LiquidStaking {
        let admin_addr = signer::address_of(admin);
        assert!(admin_addr == ADMIN_ADDRESS, error::permission_denied(EINVALID_ADMIN));
        assert!(is_initialized(), error::not_found(ECONTRACT_NOT_INITIALIZED));

        if (can_claim_rewards()) {
            let liquid_staking = borrow_global_mut<LiquidStaking>(ADMIN_ADDRESS);
            let metadata = coin::metadata(@initia_std, string::utf8(b"INIT"));
            let (_, current_time) = block::get_block_info();
            
            // Claim rewards from validator
            staking::claim_reward_script(
                admin,
                metadata,
                liquid_staking.validator
            );

            // Get claimed reward amount
            let reward_amount = coin::balance(admin_addr, metadata);
            assert!(reward_amount > 0, error::invalid_argument(EZERO_REWARD));

            // Distribute rewards
            distribute_rewards(admin, reward_amount, metadata);

            // Update last claim timestamp
            liquid_staking.last_reward_claim = current_time;
        }
    }

    /// Distribute rewards according to policy
    fun distribute_rewards(
        admin: &signer,
        total_reward: u64,
        metadata: Object<fungible_asset::Metadata>
    ) {
        let admin_addr = signer::address_of(admin);

        // Calculate shares
        let mev_amount = (total_reward * MEV_BIDDING_RATIO) / RATIO_SCALE;
        let protocol_amount = (total_reward * PROTOCOL_FEE_RATIO) / RATIO_SCALE;
        let lp_amount = (total_reward * LP_REWARD_RATIO) / RATIO_SCALE;

        // 1. Send to MEV bidding pool
        if (mev_amount > 0) {
            let mev_coins = coin::withdraw(admin, metadata, mev_amount);
            // Store in contract for MEV bidding
            coin::deposit(ADMIN_ADDRESS, mev_coins);
        };

        // 2. Send protocol fee to treasury
        if (protocol_amount > 0) {
            let protocol_coins = coin::withdraw(admin, metadata, protocol_amount);
            coin::deposit(ADMIN_ADDRESS, protocol_coins);
        };

        // 3. Distribute to LPs based on their shares
        if (lp_amount > 0) {
            let lp_coins = coin::withdraw(admin, metadata, lp_amount);
            distribute_to_lps(lp_coins);
        };

        let (_, current_time) = block::get_block_info();
        
        // Emit distribution event
        event::emit(RewardDistributedEvent {
            total_amount: total_reward,
            mev_amount,
            protocol_amount,
            lp_amount,
            timestamp: current_time
        });
    }

    /// Distribute rewards to liquidity providers based on their shares
    fun distribute_to_lps(lp_reward: fungible_asset::FungibleAsset) acquires LiquidStaking {
        let liquid_staking = borrow_global<LiquidStaking>(ADMIN_ADDRESS);
        
        // If no stakers, return early
        if (liquid_staking.total_staked == 0) {
            fungible_asset::destroy_zero(lp_reward);
            return
        };

        // Calculate reward per staked token
        let reward_per_token = fungible_asset::amount(&lp_reward) / liquid_staking.total_staked;
        
        // Store rewards for later distribution
        coin::deposit(ADMIN_ADDRESS, lp_reward);
    }

    /// Claim LP rewards (called by individual LPs)
    public fun claim_lp_rewards(staker: &signer) acquires LiquidStaking {
        let staker_addr = signer::address_of(staker);
        let liquid_staking = borrow_global<LiquidStaking>(ADMIN_ADDRESS);
        
        // Calculate staker's share
        // Implementation depends on how you track individual LP stakes
    }
}
