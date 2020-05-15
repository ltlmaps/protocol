pragma solidity 0.6.8;
pragma experimental ABIEncoderV2;

import "../../dependencies/TokenUser.sol";
import "../../dependencies/libs/EnumerableSet.sol";
import "../../prices/IValueInterpreter.sol";
import "../hub/Spoke.sol";
import "./IShares.sol";
import "./SharesToken.sol";

/// @title Shares Contract
/// @author Melon Council DAO <security@meloncoucil.io>
/// @notice Buy and sell shares for a Melon fund
contract Shares is IShares, TokenUser, Spoke, SharesToken {
    using EnumerableSet for EnumerableSet.AddressSet;

    event SharesBought(
        address indexed buyer,
        uint256 sharesQuantity,
        address investmentAsset,
        uint256 investmentAmount
    );

    event SharesInvestmentAssetsDisabled (address[] assets);

    event SharesInvestmentAssetsEnabled (address[] assets);

    event SharesRedeemed(
        address indexed redeemer,
        uint256 sharesQuantity,
        address[] receivedAssets,
        uint256[] receivedAssetQuantities
    );

    address public DENOMINATION_ASSET;
    EnumerableSet.AddressSet private sharesInvestmentAssets;

    modifier onlySharesRequestor() {
        require(
            msg.sender == __getRegistry().sharesRequestor(),
            "Only SharesRequestor can call this function"
        );
        _;
    }

    constructor(
        address _hub,
        address _denominationAsset,
        address[] memory _defaultAssets,
        string memory _tokenName
    )
        public
        Spoke(_hub)
        SharesToken(_tokenName)
    {
        require(
            __getRegistry().assetIsRegistered(_denominationAsset),
            "Denomination asset must be registered"
        );
        DENOMINATION_ASSET = _denominationAsset;

        if (_defaultAssets.length > 0) {
            __enableSharesInvestmentAssets(_defaultAssets);
        }
    }

    // EXTERNAL

    /// @notice Buy shares on behalf of a specified user
    /// @dev Only callable by the SharesRequestor associated with the Registry
    /// Settles Milestone fees via getSharesCostInAsset
    /// @param _buyer The for which to buy shares
    /// @param _investmentAsset The asset with which to buy shares
    /// @param _sharesQuantity The desired amount of shares
    /// @return costInInvestmentAsset_ The amount of investment asset used to buy the desired shares
    function buyShares(
        address _buyer,
        address _investmentAsset,
        uint256 _sharesQuantity
    )
        external
        override
        onlySharesRequestor
        returns (uint256 costInInvestmentAsset_)
    {
        costInInvestmentAsset_ = getSharesCostInAsset(_sharesQuantity, _investmentAsset);

        // Issue shares and transfer investment asset to vault
        address vaultAddress = address(__getVault());
        _mint(_buyer, _sharesQuantity);
        __safeTransferFrom(_investmentAsset, msg.sender, address(this), costInInvestmentAsset_);
        __increaseApproval(_investmentAsset, vaultAddress, costInInvestmentAsset_);
        IVault(vaultAddress).deposit(_investmentAsset, costInInvestmentAsset_);

        emit SharesBought(
            _buyer,
            _sharesQuantity,
            _investmentAsset,
            costInInvestmentAsset_
        );
    }

    /// @notice Disable the buying of shares with specific assets
    /// @param _assets The assets for which to disable the buying of shares
    function disableSharesInvestmentAssets(address[] calldata _assets) external onlyManager {
        require(_assets.length > 0, "disableSharesInvestmentAssets: _assets cannot be empty");

        for (uint256 i = 0; i < _assets.length; i++) {
            require(
                isSharesInvestmentAsset(_assets[i]),
                "disableSharesInvestmentAssets: Asset is not enabled"
            );
            EnumerableSet.remove(sharesInvestmentAssets, _assets[i]);
        }
        emit SharesInvestmentAssetsDisabled(_assets);
    }

    /// @notice Enable the buying of shares with specific assets
    /// @param _assets The assets for which to disable the buying of shares
    function enableSharesInvestmentAssets(address[] calldata _assets) external onlyManager {
        require(_assets.length > 0, "enableSharesInvestmentAssets: _assets cannot be empty");
        __enableSharesInvestmentAssets(_assets);
    }

    /// @notice Get all assets that can be used to buy shares
    /// @return The assets that can be used to buy shares
    function getSharesInvestmentAssets() external view returns (address[] memory) {
        return EnumerableSet.enumerate(sharesInvestmentAssets);
    }

    /// @notice Redeem all of the sender's shares for a proportionate slice of the fund's assets
    function redeemShares() external {
        __payoutSellSharesFees(msg.sender, balanceOf(msg.sender));
        __redeemShares(balanceOf(msg.sender), false);
    }

    /// @notice Redeem all of the sender's shares for a proportionate slice of the fund's assets
    /// @dev _bypassFailure is set to true, the user will lose their claim to any assets for
    /// which the transfer function fails.
    function redeemSharesEmergency() external {
        __payoutSellSharesFees(msg.sender, balanceOf(msg.sender));
        __redeemShares(balanceOf(msg.sender), true);
    }

    /// @notice Redeem a specified quantity of the sender's shares
    /// for a proportionate slice of the fund's assets
    /// @param _sharesQuantity Number of shares
    function redeemSharesQuantity(uint256 _sharesQuantity) external {
         __payoutSellSharesFees(msg.sender, _sharesQuantity);
        __redeemShares(_sharesQuantity, false);
    }

    // PUBLIC FUNCTIONS

    /// @notice Calculate the overall GAV of the fund
    /// @return gav_ The fund GAV
    function calcGav() public view returns (uint256) {
        IVault vault = __getVault();
        IValueInterpreter valueInterpreter = __getValueInterpreter();
        address[] memory assets = vault.getOwnedAssets();
        uint256[] memory balances = vault.getAssetBalances(assets);

        uint256 gav;
        for (uint256 i = 0; i < assets.length; i++) {
            (
                uint256 assetGav,
                bool isValid
            ) = valueInterpreter.calcCanonicalAssetValue(
                assets[i],
                balances[i],
                DENOMINATION_ASSET
            );
            require(assetGav > 0 && isValid, "calcGav: No valid price available for asset");

            gav = add(gav, assetGav);
        }

        return gav;
    }

    /// @notice Calculate the cost for a given number of shares in the fund, in a given asset
    /// @dev Pays all milestone fees prior to calculations
    /// @param _sharesQuantity Number of shares
    /// @param _asset Asset in which to calculate share cost
    /// @return The amount of the asset required to buy the quantity of shares
    function getSharesCostInAsset(uint256 _sharesQuantity, address _asset)
        public
        override
        returns (uint256)
    {
        // First, need to payout all due milestone-based fees to fully dilute supply
        payoutMilestoneFeesForFund();

        uint256 denominatedSharePrice;
        if (totalSupply() == 0) {
            denominatedSharePrice = 10 ** uint256(ERC20WithFields(DENOMINATION_ASSET).decimals());
        }
        else {
            denominatedSharePrice = calcGav() * 10 ** uint256(decimals) / totalSupply();
        }

        // TOOD: does it matter if we do: cost of 1 share x quantity vs. GAV x shares / supply (b/c rounding)?
        // Because 1 share will be rounded down, and then multiplied, which could yield a slightly smaller number
        uint256 denominationAssetQuantity = mul(
            _sharesQuantity,
            denominatedSharePrice
        ) / 10 ** uint256(decimals);

        if (_asset == DENOMINATION_ASSET) return denominationAssetQuantity;

        (uint256 assetQuantity,) = __getValueInterpreter().calcCanonicalAssetValue(
            DENOMINATION_ASSET,
            denominationAssetQuantity,
            _asset
        );
        return assetQuantity;
    }

    /// @notice Confirm whether asset can be used to buy shares
    /// @param _asset The asset to confirm
    /// @return True if the asset can be used to buy shares
    function isSharesInvestmentAsset(address _asset) public view override returns (bool) {
        return EnumerableSet.contains(sharesInvestmentAssets, _asset);
    }

    /// @notice Pays due milestone-based fees to the fund manager.
    /// @dev Mints new shares. Callable by anyone.
    function payoutMilestoneFeesForFund() public {
        uint256 sharesDue = __getFeeManager().settleFeesForFund(IFeeManager.FeeHook.Milestone);
        if (sharesDue > 0) {
            _mint(__getHub().MANAGER(), sharesDue);
        }
    }

    // PRIVATE FUNCTIONS

    /// @notice Enable assets with which to buy shares
    function __enableSharesInvestmentAssets (address[] memory _assets) private {
        for (uint256 i = 0; i < _assets.length; i++) {
            require(
                !isSharesInvestmentAsset(_assets[i]),
                "__enableSharesInvestmentAssets: Asset is already enabled"
            );
            require(
                __getRegistry().assetIsRegistered(_assets[i]),
                "__enableSharesInvestmentAssets: Asset not in Registry"
            );
            EnumerableSet.add(sharesInvestmentAssets, _assets[i]);
        }
        emit SharesInvestmentAssetsEnabled(_assets);
    }

    /// @dev This charges both Milestone fees and SellShares fee types:
    /// 1. Payout all Milestone fees that have matured (inflates shares by minting to manager)
    /// 2. Payout investor's share of non-matured Milestone fees (reallocates shares from investor to manager)
    /// 3. Payout SellShare fees for investor (reallocates shares from investor to manager)
    /// Uses try/catch, because if fees cause an error, still need to guarantee redeemability.
    function __payoutSellSharesFees(address _redeemer, uint256 _sharesQuantity) private {
        try this.payoutMilestoneFeesForFund() {}
        catch {}

        address manager = __getHub().MANAGER();
        if (_redeemer != manager) {
            uint256 totalSharesDue;
            // Milestone fees
            try __getFeeManager().settleFeesForInvestor(
                IFeeManager.FeeHook.Milestone,
                _redeemer,
                _sharesQuantity
            )
                returns (uint256 sharesDue)
            {
                totalSharesDue = sharesDue;
            }
            catch {}

            // SellShares fees
            try __getFeeManager().settleFeesForInvestor(
                IFeeManager.FeeHook.SellShares,
                _redeemer,
                _sharesQuantity
            )
                returns (uint256 sharesDue)
            {
                totalSharesDue = add(totalSharesDue, sharesDue);
            }
            catch {}

            if (totalSharesDue > 0 && balanceOf(_redeemer) >= totalSharesDue) {
                _burn(_redeemer, totalSharesDue);
                _mint(manager, totalSharesDue);
            }
        }
    }

    /// @notice Redeem a specified quantity of the sender's shares
    /// for a proportionate slice of the fund's assets
    /// @dev If _bypassFailure is set to true, the user will lose their claim to any assets for
    /// which the transfer function fails. This should always be false unless explicitly intended
    /// @param _sharesQuantity The amount of shares to redeem
    /// @param _bypassFailure True if token transfer failures should be ignored and forfeited
    function __redeemShares(uint256 _sharesQuantity, bool _bypassFailure) private {
        require(_sharesQuantity > 0, "__redeemShares: _sharesQuantity must be > 0");
        require(
            _sharesQuantity <= balanceOf(msg.sender),
            "__redeemShares: _sharesQuantity exceeds sender balance"
        );

        IVault vault = __getVault();
        address[] memory payoutAssets = vault.getOwnedAssets();
        require(payoutAssets.length > 0, "__redeemShares: payoutAssets is empty");

        // Destroy the shares
        uint256 sharesSupply = totalSupply();
        _burn(msg.sender, _sharesQuantity);

        // Calculate and transfer payout assets to redeemer
        uint256[] memory payoutQuantities = new uint256[](payoutAssets.length);
        for (uint256 i = 0; i < payoutAssets.length; i++) {
            uint256 quantityHeld = vault.assetBalances(payoutAssets[i]);
            // Redeemer's ownership percentage of asset holdings
            payoutQuantities[i] = mul(quantityHeld, _sharesQuantity) / sharesSupply;

            // Transfer payout asset to redeemer
            try vault.withdraw(payoutAssets[i], payoutQuantities[i]) {}
            catch {}

            uint256 receiverPreBalance = IERC20(payoutAssets[i]).balanceOf(msg.sender);
            try IERC20Flexible(payoutAssets[i]).transfer(msg.sender, payoutQuantities[i]) {
                uint256 receiverPostBalance = IERC20(payoutAssets[i]).balanceOf(msg.sender);
                require(
                    add(receiverPreBalance, payoutQuantities[i]) == receiverPostBalance,
                    "__redeemShares: Receiver did not receive tokens in transfer"
                );
            }
            catch {
                if (!_bypassFailure) {
                    revert("__redeemShares: Token transfer failed");
                }
            }
        }

        emit SharesRedeemed(
            msg.sender,
            _sharesQuantity,
            payoutAssets,
            payoutQuantities
        );
    }
}

contract SharesFactory {
    function createInstance(
        address _hub,
        address _denominationAsset,
        address[] calldata _defaultAssets,
        string calldata _tokenName
    )
        external
        returns (address)
    {
        return address(new Shares(_hub, _denominationAsset, _defaultAssets, _tokenName));
    }
}
