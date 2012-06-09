require File.expand_path('../configuration', __FILE__)
require "rubygems"
require "uuidtools"
require "plist"
module IOSCertEnrollment
  class Profile
    attr_accessor :url, :identifier, :display_name, :description, :icon, :payload, :organization, :expiration
    def initialize(url="")
      self.url = IOSCertEnrollment.base_url + url
      self.identifier = IOSCertEnrollment.identifier
      self.display_name = IOSCertEnrollment.display_name
      self.organization = IOSCertEnrollment.organization
      self.description = ""
      self.expiration = nil
      
    end
    
    def service
        payload = general_payload()
        payload['PayloadType'] = "Profile Service" # do not modify
        payload['PayloadIdentifier'] = self.identifier+".mobileconfig.profile-service"

        # strings that show up in UI, customizable
        payload['PayloadDisplayName'] = self.display_name
        payload['PayloadDescription'] = self.description

        payload_content = Hash.new
	      payload_content['URL'] = self.url
        payload_content['DeviceAttributes'] = [
            "UDID", 
            "VERSION",
            "PRODUCT",              # ie. iPhone1,1 or iPod2,1
            "DEVICE_NAME",          # given device name "My iPhone"
            "MAC_ADDRESS_EN0",
            "IMEI",
            "ICCID" 
            ];

        payload['PayloadContent'] = payload_content
        self.payload = Plist::Emit.dump(payload)
        return self
    end

    def encrypted_service
      ## ASA encryption_cert_payload
        payload = general_payload()

        payload['PayloadIdentifier'] = self.identifier+".encrypted-profile-service"
        payload['PayloadType'] = "Configuration" # do not modify

        # strings that show up in UI, customisable
        payload['PayloadDisplayName'] = self.display_name
        payload['PayloadDescription'] = self.description

        payload['PayloadContent'] = [encryption_cert_request("Profile Service")];
        self.payload = Plist::Emit.dump(payload)
        return self
    end


    def signed_webclip(certificates, display_name="WebClip", icon=nil)

        content_payload = general_payload()
        content_payload['PayloadIdentifier'] = self.identifier+".webclip.intranet"
        content_payload['PayloadType'] = "com.apple.webClip.managed" # do not modify

        # strings that show up in UI, customisable
        content_payload['PayloadDisplayName'] = display_name 
        content_payload['PayloadDescription'] = self.description

        # allow user to remove webclip
        content_payload['IsRemovable'] = true
        content_payload['Precomposed'] = true
        
        content_payload['Icon'] = icon if icon
        # the link
        content_payload['Label'] = display_name 
        content_payload['URL'] = self.url
        
        plist_content_payload = Plist::Emit.dump([content_payload])
        puts plist_content_payload
        
        encrypted_profile = OpenSSL::PKCS7.encrypt(certificates, plist_content_payload, OpenSSL::Cipher::Cipher::new("des-ede3-cbc"), OpenSSL::PKCS7::BINARY)
        encrypted_content = encrypted_profile.to_der

        
        
        payload = general_payload()
        payload['PayloadIdentifier'] = self.identifier+".intranet"
        payload['PayloadType'] = "Configuration" # do not modify

        # strings that show up in UI, customisable
        payload['PayloadDisplayName'] = self.display_name
        payload['PayloadDescription'] = self.description
        #payload['PayloadExpirationDate'] = self.expiration || Date.today + (360 * 10) 

        payload['EncryptedPayloadContent'] = StringIO.new(encrypted_content)
        self.payload = Plist::Emit.dump(payload)
        puts self.payload
        return self.sign
    end



    def configuration(encrypted_content)
        payload = general_payload()
        payload['PayloadIdentifier'] = self.identifier+".intranet"
        payload['PayloadType'] = "Configuration" # do not modify

        # strings that show up in UI, customisable
        payload['PayloadDisplayName'] = self.display_name
        payload['PayloadDescription'] = self.description
        payload['PayloadExpirationDate'] = self.expiration || Date.today + (360 * 10) # expire in 10 years

        payload['EncryptedPayloadContent'] = StringIO.new(encrypted_content)
        self.payload = Plist::Emit.dump(payload)
        return self
    end
    
    
    def sign
      signed_profile = OpenSSL::PKCS7.sign(SSL.certificate, SSL.key,  self.payload, [], OpenSSL::PKCS7::BINARY)
      return Certificate.new(signed_profile.to_der, "application/x-apple-aspen-config")        
      
    end
    
    def encrypt(certificates)
      encrypted_profile = OpenSSL::PKCS7.encrypt(certificates, self.payload, OpenSSL::Cipher::Cipher::new("des-ede3-cbc"), OpenSSL::PKCS7::BINARY)
      return Certificate.new(encrypted_profile.to_der, "application/x-apple-aspen-config")        
      
    end
    
    
    private
    def encryption_cert_request(purpose)
        ## AKA scep_cert_payload
        payload = general_payload()


        payload['PayloadIdentifier'] = self.identifier+".encryption-cert-request"
        payload['PayloadType'] = "com.apple.security.scep" # do not modify

        payload['PayloadDisplayName'] = purpose
        payload['PayloadDescription'] = "Provides device encryption identity"

        payload_content = Hash.new
        payload_content['URL'] = self.url
        payload_content['Subject'] = [ [ [ "O", self.organization ] ], 
            [ [ "CN", purpose + " (" + UUIDTools::UUID.random_create().to_s + ")" ] ] ];

        payload_content['Keysize'] = 1024
        payload_content['Key Type'] = "RSA"
        payload_content['Key Usage'] = 5 # digital signature (1) | key encipherment (4)
        payload_content['GetCACaps'] = ["POSTPKIOperation","Renewal","SHA-1"]

        payload['PayloadContent'] = payload_content;
        payload
    end
    
    def general_payload()
        payload = Hash.new
        payload['PayloadVersion'] = 1 # do not modify
        payload['PayloadUUID'] = UUIDTools::UUID.random_create().to_s # should be unique
        payload['PayloadOrganization'] = self.organization
        payload
    end
  end
end