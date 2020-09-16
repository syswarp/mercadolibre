/*
 * To change this license header, choose License Headers in Project Properties.
 * To change this template file, choose Tools | Templates
 * and open the template in the editor.
 */
package ar.com.syswarp;

import io.swagger.client.ApiClient;
import io.swagger.client.ApiException;
import io.swagger.client.Configuration;
import io.swagger.client.api.DefaultApi;
import io.swagger.client.model.*;
import java.io.UnsupportedEncodingException;


public class DefaultApiExample {

/*Replace with your application Client Id, Client Secret and RedirectUri*/

    Long clientId = 8601632102527385L;  
    String clientSecret = "z8XeCb7x2JkUVnkGfOu8MYDoDiFNccJi";
    String redirectUri = "https://phiphitoys.com.ar/mercadolibre/";
    String site_id="8601632102527385";
    String accessToken ="la di de alta para sacar errores.";
    private final DefaultApi api = new DefaultApi();
    
    public  void getAuthUrl() throws UnsupportedEncodingException, ApiException {
           DefaultApi api = new DefaultApi(new ApiClient(), clientId, clientSecret);
           
           String response = api.getAuthUrl(redirectUri, Configuration.AuthUrls.MLA);
    }
    
    public  void getAccessToken(String server_code) throws UnsupportedEncodingException, ApiException {
               System.out.println("Envio clientId " + clientId);
               System.out.println("Envio clientSecret " + clientSecret);

               DefaultApi api = new DefaultApi(new ApiClient(), clientId, clientSecret);
               String code = server_code;
               AccessToken response = api.authorize(code, redirectUri);
               System.out.println("Envio code " + code);
               System.out.println("Redirect URL " + code);
               
    }
     
    private  void refreshToken() throws UnsupportedEncodingException, ApiException {
                    DefaultApi api = new DefaultApi(new ApiClient(), clientId, clientSecret);
                    String refreshToken = "{your_refresh_token}";
                    RefreshToken response = api.refreshAccessToken(refreshToken);
    }
    
    private  void GET() throws ApiException {
            String resource = "{api_resource}";
            Object response = api.defaultGet(resource);
    }
    
    public void POST() throws ApiException {
            String resource = "{api_resource}";
            Object body = new Object();
           // body.field("{some_value}");
            Object response = api.defaultPost(accessToken, resource, body);
    }
        
    public void PUT() throws ApiException {
                String id = "{object_id}";
                String resource = "{api_resource}";
                Object body = new Object();
             //   body.field("{some_value}");
                Object response = api.defaultPut(resource, id, accessToken, body);
    }
    
    public void DELETE() throws ApiException {
                 String id = "{object_id}";
                 String resource = "{api_resource}";
                 Object response = api.defaultDelete(resource, id, accessToken);
    }
}