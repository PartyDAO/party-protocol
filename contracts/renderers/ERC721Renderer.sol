
import "./IERC721Renderer.sol";

contract ERC721Renderer is IERC721Renderer {
    function tokenURI(uint256 tokenId) external view returns (string memory) {
        return "<SVG></SVG>";
    }
}