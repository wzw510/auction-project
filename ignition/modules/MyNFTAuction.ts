import {buildModule} from "@nomicfoundation/hardhat-ignition/modules";
const MyNFTAuctionModule = buildModule("MyNFTAuction", (m)=>{
    const myNFTAuction = m.contract("MyNFTAuction")

    return {myNFTAuction};
})
export default MyNFTAuctionModule;