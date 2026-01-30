// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract MyNFT is ERC721,  Ownable {
    
    uint256 private _nextTokenId;
    string private _baseTokenURI;

    constructor(string memory name,string memory symbol)
    ERC721(name,symbol)
    Ownable(msg.sender){
        _nextTokenId = 1;
        _baseTokenURI = ""; 
    }

    function mint(address to) public onlyOwner returns(uint256){
        uint256 tokenId = _nextTokenId;
        _nextTokenId++;
        _safeMint(to, tokenId);
        return tokenId;
    }

    function mintBatch(address to,uint256 count)public onlyOwner{
        for(uint256 i = 0;i<=count;i++){
            mint(to);
        }
    }

    function setBaseURI(string memory baseURI) public onlyOwner{
        _baseTokenURI = baseURI;
    }

    function tokenURI(uint256 tokenId) public view override returns(string memory){
        _requireOwned(tokenId);
        return string(abi.encodePacked(_baseTokenURI,toString(tokenId)));
    }

    function toString(uint256 value) internal pure returns(string memory){
        if(value == 0){
            return "0";
        }
        uint256 temp = value;
        uint256 digits;
        while(temp != 0){
            digits++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while(value != 0){
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }
        return string(buffer);
    }


}