"use client";

import { useEffect, useState } from "react";
import { useParams } from "next/navigation";
import { supabase } from "@/utils/supabase/client";
import Image from "next/image";
import { Button } from "@/components/ui/button";
import { MapPin, Phone, Mail, Package, Calendar, Star } from "lucide-react";
import { toast } from "sonner";
import Link from "next/link";

export default function PublicProfile() {
  const params = useParams();
  const [profile, setProfile] = useState(null);
  const [listings, setListings] = useState([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    if (params.id) {
      fetchPublicProfile();
      fetchUserListings();
    }
  }, [params.id]);

  const fetchPublicProfile = async () => {
    try {
      const { data, error } = await supabase
        .from("users")
        .select("*")
        .eq("id", params.id)
        .eq("is_active", true)
        .single();

      if (error) {
        console.error("Error fetching profile:", error);
        toast.error("Profile not found");
        return;
      }

      setProfile(data);
    } catch (error) {
      console.error("Error:", error);
      toast.error("Failed to load profile");
    } finally {
      setLoading(false);
    }
  };

  const fetchUserListings = async () => {
    try {
      const { data, error } = await supabase
        .from("listing")
        .select(`
          *,
          listingImages(url, listing_id)
        `)
        .eq("user_id", params.id)
        .eq("active", true)
        .order("created_at", { ascending: false });

      if (!error && data) {
        setListings(data);
      }
    } catch (error) {
      console.error("Error fetching listings:", error);
    }
  };

  const getProfileImage = () => {
    if (!profile) return "/default-avatar.png";

    const imagePath = profile.account_type === "individual"
      ? profile.avatar_path
      : profile.business_image_path;

    if (!imagePath) return "/default-avatar.png";

    if (imagePath.startsWith("http")) return imagePath;

    const bucket = profile.account_type === "individual"
      ? "user-avatars"
      : "business-images";

    return `${process.env.NEXT_PUBLIC_SUPABASE_URL}/storage/v1/object/public/${bucket}/${imagePath}`;
  };

  const getDisplayName = () => {
    if (!profile) return "";
    return profile.account_type === "individual"
      ? profile.name
      : profile.business_name;
  };

  const copyToClipboard = (text, label) => {
    navigator.clipboard.writeText(text);
    toast.success(`${label} copied to clipboard!`);
  };

  if (loading) {
    return (
      <div className="min-h-screen flex items-center justify-center">
        <div className="text-center">
          <div className="animate-spin rounded-full h-12 w-12 border-b-2 border-primary mx-auto"></div>
          <p className="mt-4 text-gray-600">Loading profile...</p>
        </div>
      </div>
    );
  }

  if (!profile) {
    return (
      <div className="min-h-screen flex items-center justify-center">
        <div className="text-center">
          <h1 className="text-2xl font-bold text-gray-900 mb-2">Profile Not Found</h1>
          <p className="text-gray-600 mb-4">The profile you're looking for doesn't exist or is not public.</p>
          <Link href="/">
            <Button>Go Back Home</Button>
          </Link>
        </div>
      </div>
    );
  }

  return (
    <div className="min-h-screen bg-gray-50 py-8">
      <div className="max-w-4xl mx-auto px-4 sm:px-6 lg:px-8">
        {/* Profile Header */}
        <div className="bg-white rounded-lg shadow-md p-6 mb-6">
          <div className="flex flex-col md:flex-row items-center md:items-start space-y-4 md:space-y-0 md:space-x-6">
            <div className="flex-shrink-0">
              <Image
                src={getProfileImage()}
                alt={getDisplayName()}
                width={120}
                height={120}
                className="rounded-full object-cover border-4 border-gray-200"
              />
            </div>

            <div className="flex-1 text-center md:text-left">
              <h1 className="text-3xl font-bold text-gray-900 mb-2">
                {getDisplayName()}
              </h1>

              <div className="flex items-center justify-center md:justify-start mb-2">
                <span className="inline-flex items-center px-3 py-1 rounded-full text-sm font-medium bg-primary/10 text-primary capitalize">
                  {profile.account_type}
                  {profile.account_type !== "individual" && " Business"}
                </span>
              </div>

              <div className="space-y-2 text-sm text-gray-600">
                {profile.address && (
                  <div className="flex items-center justify-center md:justify-start">
                    <MapPin className="w-4 h-4 mr-2 flex-shrink-0" />
                    <span>{profile.address}</span>
                  </div>
                )}

                {profile.phone && (
                  <div className="flex items-center justify-center md:justify-start">
                    <Phone className="w-4 h-4 mr-2 flex-shrink-0" />
                    <button
                      onClick={() => copyToClipboard(profile.phone, "Phone number")}
                      className="hover:text-primary hover:underline"
                    >
                      {profile.phone}
                    </button>
                  </div>
                )}

                <div className="flex items-center justify-center md:justify-start">
                  <Mail className="w-4 h-4 mr-2 flex-shrink-0" />
                  <button
                    onClick={() => copyToClipboard(profile.email, "Email")}
                    className="hover:text-primary hover:underline"
                  >
                    {profile.email}
                  </button>
                </div>

                <div className="flex items-center justify-center md:justify-start">
                  <Calendar className="w-4 h-4 mr-2 flex-shrink-0" />
                  <span>Member since {new Date(profile.created_at).toLocaleDateString()}</span>
                </div>
              </div>
            </div>

            <div className="flex flex-col space-y-2">
              <Button
                onClick={() => window.open(`mailto:${profile.email}`, '_blank')}
                className="flex items-center"
              >
                <Mail className="w-4 h-4 mr-2" />
                Contact
              </Button>

              {profile.phone && (
                <Button
                  variant="outline"
                  onClick={() => window.open(`tel:${profile.phone}`, '_blank')}
                  className="flex items-center"
                >
                  <Phone className="w-4 h-4 mr-2" />
                  Call
                </Button>
              )}
            </div>
          </div>
        </div>

        {/* Listings Section */}
        <div className="bg-white rounded-lg shadow-md p-6">
          <div className="flex items-center justify-between mb-6">
            <h2 className="text-2xl font-bold text-gray-900 flex items-center">
              <Package className="w-6 h-6 mr-2" />
              Active Listings ({listings.length})
            </h2>
          </div>

          {listings.length === 0 ? (
            <div className="text-center py-8">
              <Package className="w-12 h-12 text-gray-400 mx-auto mb-4" />
              <p className="text-gray-600">No active listings at the moment.</p>
            </div>
          ) : (
            <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
              {listings.map((listing) => (
                <Link
                  key={listing.id}
                  href={`/view-details/${listing.id}`}
                  className="group"
                >
                  <div className="bg-gray-50 rounded-lg overflow-hidden hover:shadow-md transition-shadow duration-200">
                    {listing.listingImages?.[0] && (
                      <div className="aspect-w-16 aspect-h-9">
                        <Image
                          src={listing.listingImages[0].url}
                          alt={listing.title || "Listing"}
                          width={300}
                          height={200}
                          className="w-full h-48 object-cover group-hover:scale-105 transition-transform duration-200"
                        />
                      </div>
                    )}

                    <div className="p-4">
                      <div className="flex items-center justify-between mb-2">
                        <span className="text-lg font-semibold text-gray-900">
                          {listing.price ? `${listing.price} EGP` : "Free"}
                        </span>
                        <span className={`text-xs px-2 py-1 rounded-full ${
                          listing.type === "Donate"
                            ? "bg-green-100 text-green-800"
                            : "bg-blue-100 text-blue-800"
                        }`}>
                          {listing.type}
                        </span>
                      </div>

                      <p className="text-sm text-gray-600 mb-2 line-clamp-2">
                        {listing.description}
                      </p>

                      <div className="flex items-center justify-between text-xs text-gray-500">
                        <span>{listing.surplusType}</span>
                        <span>{listing.condition}</span>
                      </div>
                    </div>
                  </div>
                </Link>
              ))}
            </div>
          )}
        </div>
      </div>
    </div>
  );
}