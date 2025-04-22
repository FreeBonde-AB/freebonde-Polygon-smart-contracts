solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Pausable.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

contract GrowingSlotNFT is ERC721, AccessControl, ERC721Enumerable, ERC721Pausable {
    using Counters for Counters.Counter;
    using Strings for uint256;

    Counters.Counter private _tokenIdCounter;

    // Roles
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    // Growing Slot Information
    struct GrowingSlot {
        uint256 farmId;
        string cropType;
        string status;
    }
    mapping(uint256 => GrowingSlot) public growingSlots;

    event GrowingSlotMinted(address indexed to, uint256 tokenId, uint256 farmId);
    event GrowingSlotInfoUpdated(uint256 indexed tokenId, string cropType, string status);

    constructor() ERC721("GrowingSlotNFT", "GSNFT") {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(MINTER_ROLE, msg.sender);
        _grantRole(PAUSER_ROLE, msg.sender);
    }

    function safeMint(address to, uint256 farmId) external onlyRole(MINTER_ROLE) {
        uint256 tokenId = _tokenIdCounter.current();
        _tokenIdCounter.increment();
        _safeMint(to, tokenId);
        growingSlots[tokenId] = GrowingSlot(farmId, "", ""); // Initialize with empty crop type and status

        emit GrowingSlotMinted(to, tokenId, farmId);
    }

    function updateGrowingSlotInfo(
        uint256 tokenId,
        string memory cropType,
        string memory status
    ) external {
        require(_exists(tokenId), "Token does not exist");
        require(ownerOf(tokenId) == msg.sender, "You are not the owner");

        growingSlots[tokenId].cropType = cropType;
        growingSlots[tokenId].status = status;

        emit GrowingSlotInfoUpdated(tokenId, cropType, status);
    }

    function getGrowingSlotInfo(uint256 tokenId)
        external
        view
        returns (
            uint256,
            string memory,
            string memory
        )
    {
        require(_exists(tokenId), "Token does not exist");
        return (growingSlots[tokenId].farmId, growingSlots[tokenId].cropType, growingSlots[tokenId].status);
    }

    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    function _beforeTokenTransfer(address from, address to, uint256 tokenId)
        internal
        override(ERC721, ERC721Enumerable, ERC721Pausable)
        whenNotPaused
    {
        super._beforeTokenTransfer(from, to, tokenId);
    }
    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721, AccessControl, ERC721Enumerable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}
