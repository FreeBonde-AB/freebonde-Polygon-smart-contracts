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

contract DigitalFarmNFT is ERC721, AccessControl, ERC721Enumerable, ERC721Pausable {
    using Counters for Counters.Counter;
    using Strings for uint256;

    Counters.Counter private _tokenIdCounter;

    // Roles
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    // NFT Tiers
    enum Tier {
        STANDARD,
        ENHANCED,
        ADVANCED
    }

    // NFT information
    mapping(uint256 => Tier) public nftTiers;
    mapping(uint256 => string) public deviceIds;
    mapping(string => uint256) public deviceIdToTokenId; // Map from device ID to tokenId

    event NFTMinted(address indexed to, uint256 tokenId, Tier tier);
    event NFTUpgraded(uint256 indexed tokenId, Tier newTier);
    event DeviceAssociated(uint256 indexed tokenId, string deviceId);

    constructor() ERC721("DigitalFarmNFT", "DFNFT") {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(MINTER_ROLE, msg.sender);
        _grantRole(PAUSER_ROLE, msg.sender);
    }

    function safeMint(address to, string memory deviceId) public onlyRole(MINTER_ROLE) {
        require(bytes(deviceId).length > 0, "Device ID cannot be empty");
        require(deviceIdToTokenId[deviceId] == 0, "Device ID already associated");

        uint256 tokenId = _tokenIdCounter.current();
        _tokenIdCounter.increment();
        _safeMint(to, tokenId);

        nftTiers[tokenId] = Tier.STANDARD;
        deviceIds[tokenId] = deviceId;
        deviceIdToTokenId[deviceId] = tokenId;

        emit NFTMinted(to, tokenId, Tier.STANDARD);
        emit DeviceAssociated(tokenId, deviceId);
    }

    function upgrade(uint256 tokenId) external {
        require(_exists(tokenId), "Token does not exist");
        require(ownerOf(tokenId) == msg.sender, "You are not the owner");
        Tier currentTier = nftTiers[tokenId];
        require(currentTier != Tier.ADVANCED, "Already at the highest tier");

        if (currentTier == Tier.STANDARD) {
            nftTiers[tokenId] = Tier.ENHANCED;
        } else if (currentTier == Tier.ENHANCED) {
            nftTiers[tokenId] = Tier.ADVANCED;
        }

        emit NFTUpgraded(tokenId, nftTiers[tokenId]);
    }

    function getTier(uint256 tokenId) external view returns (Tier) {
        require(_exists(tokenId), "Token does not exist");
        return nftTiers[tokenId];
    }

    function getDeviceId(uint256 tokenId) external view returns (string memory) {
        require(_exists(tokenId), "Token does not exist");
        return deviceIds[tokenId];
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

    function setDeviceId(uint256 tokenId, string memory newDeviceId) external onlyRole(DEFAULT_ADMIN_ROLE){
        require(_exists(tokenId), "Token does not exist");
        require(bytes(newDeviceId).length > 0, "Device ID cannot be empty");
        require(deviceIdToTokenId[newDeviceId] == 0, "Device ID already associated");
        delete deviceIdToTokenId[deviceIds[tokenId]]; //delete old
        deviceIds[tokenId] = newDeviceId;
        deviceIdToTokenId[newDeviceId] = tokenId;
        emit DeviceAssociated(tokenId, newDeviceId);
    }
}
