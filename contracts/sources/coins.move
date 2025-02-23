module optia::coins {
    use std::string;
    use std::option;
    use std::signer;
    use std::error;
    use initia_std::coin::{Self, MintCapability, BurnCapability, FreezeCapability};
    use initia_std::object::Object;
    use initia_std::fungible_asset::{Self, Metadata};
    
    /// Staked token type
    struct OPINIT has store {}

    /// Name of the staked token
    const STAKED_TOKEN_NAME: vector<u8> = b"opINIT";
    /// Symbol of the staked token
    const STAKED_TOKEN_SYMBOL: vector<u8> = b"opINIT";
    /// Number of decimal places
    const TOKEN_DECIMALS: u8 = 6;

    /// URI for token icon
    const TOKEN_ICON_URI: vector<u8> = b"https://raw.githubusercontent.com/optia-labs/optia/refs/heads/main/optia.png";
    /// URI for project information
    const PROJECT_URI: vector<u8> = b"https://github.com/optia-labs/optia";

    /// Error if caller is not the admin
    const ENOT_ADMIN: u64 = 1;
    /// Error if metadata is not found
    const EMETADATA_NOT_FOUND: u64 = 2;
    /// Error if capabilities are not found
    const ECAPS_NOT_FOUND: u64 = 3;

    /// Stores capabilities for opINIT token
    struct CoinCaps has key {
        staked_burn_cap: BurnCapability,
        staked_freeze_cap: FreezeCapability,
        staked_mint_cap: MintCapability,
        staked_metadata: Object<Metadata>
    }

    /// Initializes opINIT token with capabilities
    fun init_module(sender: &signer) {
        let sender_addr = signer::address_of(sender);
        assert!(sender_addr == @optia, error::permission_denied(ENOT_ADMIN));

        let (staked_mint_cap, staked_burn_cap, staked_freeze_cap, _staked_extend_ref) = coin::initialize_and_generate_extend_ref(
            sender,
            option::none(),
            string::utf8(STAKED_TOKEN_NAME),
            string::utf8(STAKED_TOKEN_SYMBOL),
            TOKEN_DECIMALS,
            string::utf8(TOKEN_ICON_URI),
            string::utf8(PROJECT_URI)
        );

        let staked_metadata = coin::metadata(sender_addr, string::utf8(STAKED_TOKEN_SYMBOL));

        move_to(sender, CoinCaps {
            staked_burn_cap,
            staked_freeze_cap,
            staked_mint_cap,
            staked_metadata
        });
    }

    /// Mints opINIT tokens
    /// @param amount The amount of tokens to mint
    /// @return The minted fungible asset
    public fun mint_staked_init(amount: u64): fungible_asset::FungibleAsset acquires CoinCaps {
        let caps = borrow_global<CoinCaps>(@optia);
        coin::mint(&caps.staked_mint_cap, amount)
    }

    /// Burns opINIT tokens
    /// @param coins The fungible asset to burn
    public fun burn_staked_init(coins: fungible_asset::FungibleAsset) acquires CoinCaps {
        let caps = borrow_global<CoinCaps>(@optia);
        coin::burn(&caps.staked_burn_cap, coins);
    }

    /// Gets the metadata for opINIT token
    /// @return The metadata object
    public fun get_staked_init_metadata(): Object<Metadata> acquires CoinCaps {
        borrow_global<CoinCaps>(@optia).staked_metadata
    }
} 