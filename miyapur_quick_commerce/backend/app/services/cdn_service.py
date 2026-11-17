import os
from typing import Optional

class CDNService:
    """
    Production Image CDN & Asset Optimization Service.
    - Cloudinary / AWS S3 Image CDN Transformation
    - Auto WebP & Format Optimization
    - Quality Caching & High-Res Quick Commerce Thumbnails
    """

    @staticmethod
    def get_optimized_image_url(
        original_url: str,
        width: int = 500,
        quality: int = 80,
        format_type: str = "webp"
    ) -> str:
        if not original_url:
            return "https://images.unsplash.com/photo-1592924357228-91a4daadcfea?w=500&q=80"

        # If Cloudinary CDN is configured
        cloudinary_cloud = os.getenv("CLOUDINARY_CLOUD_NAME", "")
        if cloudinary_cloud and "cloudinary.com" in original_url:
            return f"https://res.cloudinary.com/{cloudinary_cloud}/image/upload/w_{width},q_{quality},f_{format_type}/{original_url.split('/')[-1]}"

        # Unsplash / External CDN Optimization
        if "unsplash.com" in original_url:
            clean_url = original_url.split("?")[0]
            return f"{clean_url}?w={width}&q={quality}&fm={format_type}"

        return original_url

cdn_service = CDNService()
