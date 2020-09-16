/*
 * To change this license header, choose License Headers in Project Properties.
 * To change this template file, choose Tools | Templates
 * and open the template in the editor.
 */
package ar.com.syswarp;

import com.google.gson.Gson;
import com.google.gson.JsonElement;
import com.google.gson.JsonObject;
import com.google.gson.JsonParser;
import java.util.Properties;

import java.io.BufferedReader;
import java.io.FileNotFoundException;
import java.io.IOException;
import java.io.InputStreamReader;
import java.net.URL;
import java.net.URLConnection;
import org.json.simple.JSONArray;
import org.json.simple.JSONObject;
import org.json.simple.parser.JSONParser;
import org.json.simple.parser.ParseException;


import io.swagger.client.ApiClient;
import io.swagger.client.ApiException;
import io.swagger.client.Configuration;
import io.swagger.client.api.DefaultApi;
import io.swagger.client.model.*;
import java.io.UnsupportedEncodingException;
import java.sql.Connection;
import java.sql.DatabaseMetaData;
import java.sql.DriverManager;
import java.sql.SQLException;

/**
 *
 * @author Administrador
 * 
 * INformacion personal//  curl  -X GET https://api.mercadolibre.com/users/me?access_token=APP_USR-8601632102527385-091516-cecf275a6eab30fbb8132bcf0b7b21c3-82263846
 * 
 * 
 * 
 */
public class Mercadolibre {

    private static Properties PROPS;
    private static String URL_APLICACIONES;
    private static String ID_APLICACION;
    private static Connection CONN;
    //private final DefaultApi api = new DefaultApi();
    
    
    public Connection DBConnect() throws ClassNotFoundException, SQLException{
      Class.forName("com.microsoft.sqlserver.jdbc.SQLServerDriver");
       Connection conn = null;
 
        try {
 //WIN-U2N1V80PNTA\MSSQLSERVER2012
            String dbURL = "jdbc:sqlserver://WIN-U2N1V80PNTA\\MSSQLSERVER2012;databaseName=mercadolibre";
            String user = "ml";
            String pass = "NoTengo1$";
            conn = DriverManager.getConnection(dbURL, user, pass);
            if (conn != null) {
                DatabaseMetaData dm = (DatabaseMetaData) conn.getMetaData();
                System.out.println("Driver name: " + dm.getDriverName());
                System.out.println("Driver version: " + dm.getDriverVersion());
                System.out.println("Product name: " + dm.getDatabaseProductName());
                System.out.println("Product version: " + dm.getDatabaseProductVersion());
            }
 
        } catch (SQLException ex) {
            ex.printStackTrace();
        } finally {
           return conn;
        }
    }
    
    
    
    
    
    
    
    public String getURI() {
        String salida = "NOOK";
        try {
            PROPS = new Properties();
            PROPS.load(Mercadolibre.class.getResourceAsStream("system.properties"));
            salida = PROPS.getProperty("ml.uri").trim();
        } catch (Exception ex) {
            System.out.println("Problemas getURI " + ex);
        }
        return salida;
    }

    public String getAPPID() {
        String salida = "NOOK";
        try {
            PROPS = new Properties();
            PROPS.load(Mercadolibre.class.getResourceAsStream("system.properties"));
            salida = PROPS.getProperty("ml.appid").trim();
        } catch (Exception ex) {
            System.out.println("Problemas getAPPID " + ex);
        }
        return salida;
    }

    public String getSecret() {
        String salida = "NOOK";
        try {
            PROPS = new Properties();
            PROPS.load(Mercadolibre.class.getResourceAsStream("system.properties"));
            salida = PROPS.getProperty("ml.clave").trim();
        } catch (Exception ex) {
            System.out.println("Problemas getSecret " + ex);
        }
        return salida;
    }

    public String Inicial() {
        String URL_APLICACION;
        String salida = "NOOK";
        try {
            PROPS = new Properties();
            PROPS.load(Mercadolibre.class.getResourceAsStream("system.properties"));
            URL_APLICACIONES = PROPS.getProperty("ml.urlapp").trim();
            ID_APLICACION = PROPS.getProperty("ml.appid").trim();

            // test conexion a la db
            //DBConnect();
            
            
            URL_APLICACION = URL_APLICACIONES + ID_APLICACION;

            String command = URL_APLICACION;
            Process process = Runtime.getRuntime().exec(command);
            //String json = process.getInputStream();
            JSONParser parser = new JSONParser();

            BufferedReader in = new BufferedReader(new InputStreamReader(process.getInputStream()));

            String inputLine;
            while ((inputLine = in.readLine()) != null) {
                // System.out.println(inputLine);
                //JSONArray a = (JSONArray) parser.parse(inputLine);

                JsonElement jsonElement = new JsonParser().parse(inputLine);
                JsonObject jsonObject = jsonElement.getAsJsonObject();

                // devuelvo los datos
                System.out.println("id: " + jsonObject.get("id"));
                System.out.println("site_id: " + jsonObject.get("site_id"));
                System.out.println("name: " + jsonObject.get("name"));
                System.out.println("description: " + jsonObject.get("description"));
                System.out.println("short_name: " + jsonObject.get("short_name"));
                System.out.println("url: " + jsonObject.get("url"));
                System.out.println("callback_url: " + jsonObject.get("callback_url"));
                System.out.println("sandbox_mode: " + jsonObject.get("sandbox_mode"));
                System.out.println("active: " + jsonObject.get("active"));
                System.out.println("max_requests_per_hour: " + jsonObject.get("max_requests_per_hour"));
                System.out.println("scopes: " + jsonObject.get("scopes"));
                System.out.println("certification_status: " + jsonObject.get("certification_status"));

                String id = jsonObject.get("id").getAsString();
                String callback_url = jsonObject.get("callback_url").getAsString();
                String url = "http://auth.mercadolibre.com.ar/authorization?response_type=code&client_id=" + id + "&redirect_uri=" + callback_url;
                salida = url;

            }
            in.close();

        } catch (FileNotFoundException e) {
            e.printStackTrace();
        } catch (IOException e) {
            e.printStackTrace();

        } catch (Exception ex) {
            System.out.println("Problemas con el archivo system.properties, por favor revisar." + ex);
        }
        return salida;
    }

    public String Autenticar(String SERVER_GENERATED_AUTHORIZATION_CODE) {
        String salida = "";
        String APP_ID = getAPPID();
        String SECRET_KEY = getSecret();
        String URL = getURI();
        try {
            //C:\datos
            
            salida = "";
            salida += "curl -X POST ";
            salida += "-H \"accept:application/json\" ";
            salida += "-H \"content-type:application/x-www-form-urlencoded\" ";
            salida += "\"https://api.mercadolibre.com/oauth/token\" ";
            salida += "-d \"grant_type=authorization_code\" ";
            salida += "-d \"client_id=" + APP_ID + "\" ";
            salida += "-d \"client_secret=" + SECRET_KEY + "\" ";
            salida += "-d \"code=" + SERVER_GENERATED_AUTHORIZATION_CODE + "\" ";
            salida += "-d \"redirect_uri=" + URL + "\"";

            String command = salida;

         Process process = Runtime.getRuntime().exec(command);
            //String json = process.getInputStream();
            JSONParser parser = new JSONParser();

            BufferedReader in = new BufferedReader(new InputStreamReader(process.getInputStream()));

            String inputLine;
            while ((inputLine = in.readLine()) != null) {

                JsonElement jsonElement = new JsonParser().parse(inputLine);
                JsonObject jsonObject = jsonElement.getAsJsonObject();

                // devuelvo los datos
                System.out.println("access_token: " + jsonObject.get("access_token"));
                
                String access_token =  jsonObject.get("access_token").getAsString();
                salida = access_token;

            }
            in.close();

        } catch (FileNotFoundException e) {
            e.printStackTrace();
        } catch (IOException e) {
            e.printStackTrace();

        } catch (Exception ex) {
            System.out.println("Problemas Autenticar(), por favor revisar." + ex);
        }


            
        
    

        return salida;

    }

}
