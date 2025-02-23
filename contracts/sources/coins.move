module optia::coins {
    use std::string;
    use std::option;
    use std::signer;
    use initia_std::coin::{Self, MintCapability, BurnCapability, FreezeCapability};
    use initia_std::object::Object;
    use initia_std::fungible_asset::{Self, Metadata};
    
    struct INIT has store {}
    struct StakedINIT has store {}

    struct CoinCaps has key {
        init_burn_cap: BurnCapability,
        init_freeze_cap: FreezeCapability,
        init_mint_cap: MintCapability,
        staked_burn_cap: BurnCapability,
        staked_freeze_cap: FreezeCapability,
        staked_mint_cap: MintCapability,
        init_metadata: Object<Metadata>,
        staked_metadata: Object<Metadata>
    }

    fun init_module(sender: &signer) {
        let sender_addr = signer::address_of(sender);
        assert!(sender_addr == @optia, 0);

        let (init_mint_cap, init_burn_cap, init_freeze_cap, _init_extend_ref) = coin::initialize_and_generate_extend_ref(
            sender,
            option::none(),
            string::utf8(b"Initia Token"),
            string::utf8(b"INIT"),
            8,
            string::utf8(b""),
            string::utf8(b"https://initia.com")
        );

        let init_metadata = coin::metadata(sender_addr, string::utf8(b"INIT"));

        let (staked_mint_cap, staked_burn_cap, staked_freeze_cap, _staked_extend_ref) = coin::initialize_and_generate_extend_ref(
            sender,
            option::none(),
            string::utf8(b"opINIT"),
            string::utf8(b"opINIT"),
            8,
            string::utf8(b"https://raw.githubusercontent.com/optia-labs/optia/refs/heads/main/optia.png"),
            string::utf8(b"https://github.com/optia-labs/optia")
        );

        let staked_metadata = coin::metadata(sender_addr, string::utf8(b"opINIT"));

        move_to(sender, CoinCaps {
            init_burn_cap,
            init_freeze_cap,
            init_mint_cap,
            staked_burn_cap,
            staked_freeze_cap,
            staked_mint_cap,
            init_metadata,
            staked_metadata
        });
    }

    public fun mint_init(amount: u64): fungible_asset::FungibleAsset acquires CoinCaps {
        let caps = borrow_global<CoinCaps>(@optia);
        coin::mint(&caps.init_mint_cap, amount)
    }

    public fun mint_staked_init(amount: u64): fungible_asset::FungibleAsset acquires CoinCaps {
        let caps = borrow_global<CoinCaps>(@optia);
        coin::mint(&caps.staked_mint_cap, amount)
    }

    public fun burn_init(coins: fungible_asset::FungibleAsset) acquires CoinCaps {
        let caps = borrow_global<CoinCaps>(@optia);
        coin::burn(&caps.init_burn_cap, coins);
    }

    public fun burn_staked_init(coins: fungible_asset::FungibleAsset) acquires CoinCaps {
        let caps = borrow_global<CoinCaps>(@optia);
        coin::burn(&caps.staked_burn_cap, coins);
    }

    public fun get_init_metadata(): Object<Metadata> acquires CoinCaps {
        borrow_global<CoinCaps>(@optia).init_metadata
    }

    public fun get_staked_init_metadata(): Object<Metadata> acquires CoinCaps {
        borrow_global<CoinCaps>(@optia).staked_metadata
    }
} 