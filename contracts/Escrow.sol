//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.14;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

interface IEscrow {

    struct Nft {
        address cAddr;
        uint tokenId;
    }

    struct Pouch {
        address cAddr;
        uint value;
    }

    struct Bundle {
        Nft[] nfts;
        Pouch[] pouches;
    }

    struct DefinedOffer {
        string name;
        address maker;
        uint displayedOfferId;
        Bundle bundle;
        bool available;
    }

    struct DisplayedOffer {
        string name;
        address maker;
        Bundle bundle;
        bool available;
    }

    function definedOffers(uint index) external view returns(string memory, address, uint, Bundle memory, bool);

    function displayedOffers(uint index) external view returns(string memory, address,Bundle memory, bool);

    function displayOffer(string calldata name, Bundle calldata bundle) external;

    function defineOffer(string calldata name, uint displayedOfferId, Bundle calldata bundle) external;

    function cancelDisplayedOffer(uint displayedOfferId) external;

    function cancelDefinedOffer(uint definedOfferId) external;

    function acceptOffer(uint displayedOfferId, uint definedOfferId) external;

    event OfferDisplayed(string displayedOfferId, address maker, string name, Bundle bundle);
    event OfferDefined(string displayedOfferId, string definedOfferId, address maker, string name, Bundle bundle);
    event OfferAccepted(string displayedOfferId, string definedOfferId);
    event DisplayedOfferCancelled(string displayedOfferId);
    event DefinedOfferCancelled(string definedOfferId);

}

contract Escrow is IEscrow, Ownable {

    using SafeERC20 for IERC20;
    using Strings for uint; 

    DefinedOffer[] public definedOffers;
    DisplayedOffer[] public displayedOffers;

    function displayOffer(string calldata name, Bundle calldata bundle) external {
        address maker = msg.sender;
        uint displayedOfferId = displayedOffers.length;
        DisplayedOffer storage displayedOffer = displayedOffers.push();
        displayedOffer.maker = maker;
        displayedOffer.name = name;
        displayedOffer.available = true;
        _saveBundle(displayedOffer.bundle, bundle);
        _transferBundle(msg.sender, address(this), bundle);
        emit OfferDisplayed(displayedOfferId.toString(), maker, name, bundle);
    }

    function defineOffer(string calldata name, uint displayedOfferId, Bundle calldata bundle) external {
        require(displayedOfferId < displayedOffers.length, "Cannot make defined offer on non existent displayed offer");
        address maker = msg.sender;
        uint definedOfferId = definedOffers.length;
        DefinedOffer storage definedOffer = definedOffers.push();
        definedOffer.maker = maker;
        definedOffer.name = name;
        definedOffer.available = true;
        definedOffer.displayedOfferId = displayedOfferId;
        _saveBundle(definedOffer.bundle, bundle);
        _transferBundle(msg.sender, address(this), bundle);
        emit OfferDefined(displayedOfferId.toString(), definedOfferId.toString(), maker, name, bundle);
    }

    function cancelDisplayedOffer(uint displayedOfferId) external {
        DisplayedOffer storage displayedOffer = displayedOffers[displayedOfferId];
        require(msg.sender == displayedOffer.maker, "Can only remove own displayed offers");
        require(displayedOffer.available, "Displayed offer is already inactive.");
        displayedOffer.available = false;
        _transferBundle(address(this), msg.sender, displayedOffer.bundle);
        emit DisplayedOfferCancelled(displayedOfferId.toString());
    }

    function cancelDefinedOffer(uint definedOfferId) external {
        DefinedOffer storage definedOffer = definedOffers[definedOfferId];
        require(msg.sender == definedOffer.maker, "Can only remove own defined offers");
        require(definedOffer.available, "Defined offer is already inactive.");
        definedOffer.available = false;
        _transferBundle(address(this), msg.sender, definedOffer.bundle);
        emit DefinedOfferCancelled(definedOfferId.toString());
    }

    function acceptOffer(uint displayedOfferId, uint definedOfferId) external {

        DisplayedOffer storage displayedOffer = displayedOffers[displayedOfferId];
        require(msg.sender == displayedOffer.maker, "Can only manage own displayed offers");
        require(displayedOffer.available, "Displayed offer is inactive.");
        displayedOffer.available = false;

        DefinedOffer storage definedOffer = definedOffers[definedOfferId];
        require(definedOffer.available, "Defined offer is inactive.");
        require(definedOffer.displayedOfferId == displayedOfferId, "The offerer did not specify your displayed offer as the taker.");
        definedOffer.available = false;

        _transferBundle(address(this), definedOffer.maker, displayedOffer.bundle);
        _transferBundle(address(this), displayedOffer.maker, definedOffer.bundle);

        emit OfferAccepted(displayedOfferId.toString(), definedOfferId.toString());

    }

    function _transferBundle(address from, address to, Bundle memory bundle) private {

        Nft[] memory nfts = bundle.nfts;
        Pouch[] memory pouches = bundle.pouches;

        for(uint i; i < nfts.length; i ++) {
            Nft memory nft = nfts[i];
            _transferNftFrom(nft.cAddr, from, to, nft.tokenId);
        }

        for(uint i; i < pouches.length; i ++) {
            Pouch memory pouch = pouches[i];
            IERC20(pouch.cAddr).safeTransferFrom(from, to, pouch.value);
        }

    }

    function _saveBundle(Bundle storage saveTo, Bundle calldata save) private {
        for(uint i; i < save.nfts.length; i ++) {
            saveTo.nfts.push(save.nfts[i]);
        }
        for(uint i; i < save.pouches.length; i ++) {
            saveTo.pouches.push(save.pouches[i]);
        }
    }

    function _transferNftFrom(address nft, address from, address to, uint tokenId) private {
        bool isERC721 = IERC165(nft).supportsInterface(type(IERC721).interfaceId);
        if(isERC721) {
            IERC721(nft).safeTransferFrom(from, to, tokenId);
        } else {
            IERC1155(nft).safeTransferFrom(from, to, tokenId, 1, "");
        }
    }



}