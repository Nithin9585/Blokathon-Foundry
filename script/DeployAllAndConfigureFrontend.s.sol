// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {BaseScript} from "./Base.s.sol";
import {Diamond} from "src/Diamond.sol";
import {IDiamondCut} from "src/facets/baseFacets/cut/IDiamondCut.sol";
import {DiamondCutFacet} from "src/facets/baseFacets/cut/DiamondCutFacet.sol";
import {
    DiamondLoupeFacet
} from "src/facets/baseFacets/loupe/DiamondLoupeFacet.sol";
import {
    OwnershipFacet
} from "src/facets/baseFacets/ownership/OwnershipFacet.sol";
import {
    DiamondRWAYieldFacetV2
} from "src/facets/utilityFacets/diamondRWA/DiamondRWAYieldFacetV2.sol";
import {IDiamondRWA} from "src/facets/utilityFacets/diamondRWA/IDiamondRWA.sol";
import {
    MockRWAToken,
    MockOndoOUSG,
    MockOndoUSDY,
    MockFigureTreasury
} from "src/mocks/MockRWAToken.sol";
import {MockUSDC} from "src/mocks/MockUSDC.sol";
import {console} from "forge-std/console.sol";

contract DeployAllAndConfigureFrontend is BaseScript {
    function run() public broadcaster {
        setUp();

        // 1. Deploy Mock USDC
        MockUSDC usdc = new MockUSDC();
        console.log("MockUSDC deployed at:", address(usdc));

        // 2. Deploy Base Facets
        DiamondCutFacet dCutFacet = new DiamondCutFacet();
        DiamondLoupeFacet dLoupeFacet = new DiamondLoupeFacet();
        OwnershipFacet dOwnershipFacet = new OwnershipFacet();

        // 3. Deploy Diamond
        IDiamondCut.FacetCut[] memory cuts = new IDiamondCut.FacetCut[](3);

        cuts[0] = IDiamondCut.FacetCut({
            facetAddress: address(dCutFacet),
            action: IDiamondCut.FacetCutAction.Add,
            functionSelectors: _generateSelectors("DiamondCutFacet")
        });

        cuts[1] = IDiamondCut.FacetCut({
            facetAddress: address(dLoupeFacet),
            action: IDiamondCut.FacetCutAction.Add,
            functionSelectors: _generateSelectors("DiamondLoupeFacet")
        });

        cuts[2] = IDiamondCut.FacetCut({
            facetAddress: address(dOwnershipFacet),
            action: IDiamondCut.FacetCutAction.Add,
            functionSelectors: _generateSelectors("OwnershipFacet")
        });

        Diamond diamond = new Diamond(deployer, cuts);
        console.log("Diamond deployed at:", address(diamond));

        // 4. Deploy RWA Facet V2
        DiamondRWAYieldFacetV2 rwaFacet = new DiamondRWAYieldFacetV2();
        console.log("DiamondRWAYieldFacetV2 deployed at:", address(rwaFacet));

        // 5. Deploy Mock RWAs
        MockOndoOUSG ousg = new MockOndoOUSG(address(usdc));
        MockOndoUSDY usdy = new MockOndoUSDY(address(usdc));
        MockFigureTreasury figure = new MockFigureTreasury(address(usdc));
        console.log("Mock RWAs deployed");

        // 6. Add RWA Facet to Diamond
        IDiamondCut.FacetCut[] memory rwaCut = new IDiamondCut.FacetCut[](1);
        rwaCut[0] = _getRWAFacetCut(address(rwaFacet));
        IDiamondCut(address(diamond)).diamondCut(rwaCut, address(0), "");

        // 7. Initialize Diamond
        IDiamondRWA(address(diamond)).initialize(
            address(usdc),
            address(ousg),
            "Ondo OUSG"
        );

        // 8. Whitelist other RWAs
        IDiamondRWA(address(diamond)).addRWAToWhitelist(
            address(usdy),
            "Ondo USDY"
        );
        IDiamondRWA(address(diamond)).addRWAToWhitelist(
            address(figure),
            "Figure Treasury"
        );

        console.log("Diamond initialized and RWAs whitelisted");

        // 9. Write addresses to frontend config
        string memory json = "{";
        json = string.concat(
            json,
            '"diamond": "',
            vm.toString(address(diamond)),
            '",'
        );
        json = string.concat(
            json,
            '"usdc": "',
            vm.toString(address(usdc)),
            '",'
        );
        json = string.concat(json, '"rwa": {');
        json = string.concat(
            json,
            '"ousg": "',
            vm.toString(address(ousg)),
            '",'
        );
        json = string.concat(
            json,
            '"usdy": "',
            vm.toString(address(usdy)),
            '",'
        );
        json = string.concat(
            json,
            '"figure": "',
            vm.toString(address(figure)),
            '"'
        );
        json = string.concat(json, "}");
        json = string.concat(json, "}");

        vm.writeFile("../frontend/src/config/deployments.json", json);
        console.log(
            "Frontend config written to ../frontend/src/config/deployments.json"
        );
    }

    function _generateSelectors(
        string memory facetName
    ) internal pure returns (bytes4[] memory selectors) {
        if (
            keccak256(bytes(facetName)) == keccak256(bytes("DiamondCutFacet"))
        ) {
            selectors = new bytes4[](1);
            selectors[0] = IDiamondCut.diamondCut.selector;
        } else if (
            keccak256(bytes(facetName)) == keccak256(bytes("DiamondLoupeFacet"))
        ) {
            selectors = new bytes4[](4);
            selectors[0] = DiamondLoupeFacet.facets.selector;
            selectors[1] = DiamondLoupeFacet.facetFunctionSelectors.selector;
            selectors[2] = DiamondLoupeFacet.facetAddresses.selector;
            selectors[3] = DiamondLoupeFacet.facetAddress.selector;
        } else if (
            keccak256(bytes(facetName)) == keccak256(bytes("OwnershipFacet"))
        ) {
            selectors = new bytes4[](2);
            selectors[0] = OwnershipFacet.transferOwnership.selector;
            selectors[1] = OwnershipFacet.owner.selector;
        }
    }

    function _getRWAFacetCut(
        address facetAddress
    ) internal pure returns (IDiamondCut.FacetCut memory) {
        bytes4[] memory selectors = new bytes4[](24);

        selectors[0] = IDiamondRWA.deposit.selector;
        selectors[1] = IDiamondRWA.withdraw.selector;
        selectors[2] = IDiamondRWA.getBestAPY.selector;
        selectors[3] = IDiamondRWA.getCurrentAPY.selector;
        selectors[4] = IDiamondRWA.getTotalAssets.selector;
        selectors[5] = IDiamondRWA.getTotalShares.selector;
        selectors[6] = IDiamondRWA.getUserShares.selector;
        selectors[7] = IDiamondRWA.previewDeposit.selector;
        selectors[8] = IDiamondRWA.previewWithdraw.selector;
        selectors[9] = IDiamondRWA.getCurrentRWA.selector;
        selectors[10] = IDiamondRWA.getWhitelistedRWAs.selector;
        selectors[11] = IDiamondRWA.isRWAWhitelisted.selector;
        selectors[12] = IDiamondRWA.getRWAInfo.selector;
        selectors[13] = IDiamondRWA.isPaused.selector;
        selectors[14] = IDiamondRWA.addRWAToWhitelist.selector;
        selectors[15] = IDiamondRWA.removeRWAFromWhitelist.selector;
        selectors[16] = IDiamondRWA.upgradeToRWA.selector;
        selectors[17] = IDiamondRWA.setPause.selector;
        selectors[18] = IDiamondRWA.setMinDeposit.selector;
        selectors[19] = IDiamondRWA.initialize.selector;
        selectors[20] = DiamondRWAYieldFacetV2.scheduleUpgrade.selector;
        selectors[21] = DiamondRWAYieldFacetV2.executeScheduledUpgrade.selector;
        selectors[22] = DiamondRWAYieldFacetV2.cancelScheduledUpgrade.selector;
        selectors[23] = DiamondRWAYieldFacetV2.getPendingUpgrade.selector;

        return
            IDiamondCut.FacetCut({
                facetAddress: facetAddress,
                action: IDiamondCut.FacetCutAction.Add,
                functionSelectors: selectors
            });
    }
}
