module optia::liquid_staking {
    use std::signer;
    use std::error;
    use initia_std::coin;
    use initia_std::event;
    use initia_std::fungible_asset;
    use initia_std::object;
    use optia::coins;

    struct LiquidStaking has key {
        total_staked: u64,
        exchange_rate: u64
    }

    #[event]
    struct StakeEvent has drop, store {
        staker: address,
        amount: u64
    }

    #[event]
    struct UnstakeEvent has drop, store {
        staker: address,
        amount: u64
    }

    const MINIMUM_STAKE: u64 = 1000000;
    const EXCHANGE_RATE_SCALE: u64 = 1000000;

    const EINVALID_AMOUNT: u64 = 1;
    const EINSUFFICIENT_BALANCE: u64 = 2;
    const ECONTRACT_NOT_INITIALIZED: u64 = 3;

    public fun initialize(admin: &signer) {
        let admin_addr = signer::address_of(admin);
        assert!(!exists<LiquidStaking>(admin_addr), error::already_exists(ECONTRACT_NOT_INITIALIZED));

        move_to(admin, LiquidStaking {
            total_staked: 0,
            exchange_rate: EXCHANGE_RATE_SCALE
        });
    }

    public fun stake(staker: &signer, amount: u64) acquires LiquidStaking {
        assert!(amount >= MINIMUM_STAKE, error::invalid_argument(EINVALID_AMOUNT));
        
        let staker_addr = signer::address_of(staker);
        let staker_account = object::address_to_object<fungible_asset::Metadata>(staker_addr);
        let staking_coin = coin::withdraw(staker, coins::get_init_metadata(), amount);
        
        let liquid_staking = borrow_global_mut<LiquidStaking>(@admin);
        let liquid_amount = (amount * liquid_staking.exchange_rate) / EXCHANGE_RATE_SCALE;
        
        coins::burn_init(staking_coin);
        let minted_coins = coins::mint_staked_init(liquid_amount);
        fungible_asset::deposit(staker_account, minted_coins);
        
        liquid_staking.total_staked = liquid_staking.total_staked + amount;
        
        event::emit(StakeEvent {
            staker: staker_addr,
            amount
        });
    }

    public fun unstake(staker: &signer, amount: u64) acquires LiquidStaking {
        let staker_addr = signer::address_of(staker);
        let staker_account = object::address_to_object<fungible_asset::Metadata>(staker_addr);
        let liquid_staking = borrow_global_mut<LiquidStaking>(@admin);
        
        let unstake_amount = (amount * EXCHANGE_RATE_SCALE) / liquid_staking.exchange_rate;
        assert!(unstake_amount <= liquid_staking.total_staked, error::invalid_argument(EINSUFFICIENT_BALANCE));
        
        let staked_coins = coin::withdraw(staker, coins::get_staked_init_metadata(), amount);
        coins::burn_staked_init(staked_coins);
        
        let init_coins = coins::mint_init(unstake_amount);
        fungible_asset::deposit(staker_account, init_coins);
        
        liquid_staking.total_staked = liquid_staking.total_staked - unstake_amount;
        
        event::emit(UnstakeEvent {
            staker: staker_addr,
            amount: unstake_amount
        });
    }

    public fun get_exchange_rate(): u64 acquires LiquidStaking {
        borrow_global<LiquidStaking>(@admin).exchange_rate
    }

    public fun get_total_staked(): u64 acquires LiquidStaking {
        borrow_global<LiquidStaking>(@admin).total_staked
    }
}
