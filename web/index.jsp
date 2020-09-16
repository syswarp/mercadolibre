<%-- 
    Document   : index
    Created on : 30/08/2020, 10:12:42
    Author     : Administrador
--%>

<%@page import="ar.com.syswarp.Mercadolibre"%>
<%@page import="java.security.SecureRandom"%>



<%@page contentType="text/html" pageEncoding="UTF-8"%>
<!DOCTYPE html>
<html>
    <head>
        <meta http-equiv="Content-Type" content="text/html; charset=UTF-8">
        <title>Mercado Libre</title>
        
<% 

  /* Logica de la llamada:
    1. tomo APP id, y lo envio para que vuelva CODE
    2. viene CODE y lo tengo que guardar.
    
    
    
    CODE=SERVER_GENERATED_AUTHORIZATION_CODE
  */  
  
  String CODE=request.getParameter("code");
  String APP_ID;  
  //SecureRandom secureRandom = SecureRandom.getInstance("NativePRNG");

  long randomLong = 9427987;//secureRandom.nextLong();
  
  Mercadolibre m = new Mercadolibre();
  APP_ID=m.Inicial();  
  
  
  if(session.getAttribute("CODE")!=null){
    CODE=session.getAttribute("CODE").toString();
    
  }

  
  
  // voy guardando variables en sesion
  // 1. 
  if(CODE!=null){
      session.setAttribute("CODE",CODE);
  }
  
  //2.
  if(APP_ID!=null){
      session.setAttribute("APP_ID",APP_ID);
  }
  
  if(APP_ID!=null && CODE!=null){ 
     String access_token=m.Autenticar( CODE );
     
     System.out.println("URL de autorizacion: "+ access_token);
     session.setAttribute("ACCESS_TOKEN",access_token);
  }
  //https://auth.mercadolibre.com.ar/authorization?response_type=code&client_id=$APP_ID&state=$RANDOM_ID&redirect_uri=$REDIRECT_URL
  
//String name=(String)session.getAttribute("sessname")
%>        
        
    </head>
    <body>
        <h1>Llamando API'S Mercado Libre</h1>
    <% if (APP_ID!=null && CODE==null){ %>      
        <h1>Primer URL de autenticacion: <%=APP_ID%></h1>
        <% response.sendRedirect(APP_ID); %>
    <% } %>        

    <% if (APP_ID!=null && CODE!=null){ %>      
        <h1>Ejecuto la llamada al token-id y me voy a la pagina principal: <%=CODE%></h1>
        <% response.sendRedirect("principal.jsp"); %>
    <% } %>        


    </body>
</html>
