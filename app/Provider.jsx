"use client";
import { LoadScript } from "@react-google-maps/api";

import Header from "./_components/Header";
import ChatBot from "./_components/ChatBot";

function Provider({ children }) {
  return (
    <div>
      <LoadScript
        googleMapsApiKey={process.env.NEXT_PUBLIC_GOOGLE_PLACE_API_KEY}
        libraries={["places"]}
      >
        <Header />
        <ChatBot />
        <div className="mt-[110px]">{children}</div>
      </LoadScript>
    </div>
  );
}

export default Provider;
